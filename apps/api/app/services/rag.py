"""L'agent : répondre en citant toujours l'ouvrage et la page.

Le fournisseur du modèle, son modèle et sa clé se règlent depuis la console
(`app/services/fournisseurs.py`). Deux fournisseurs peuvent être posés : le
second est appelé quand le disjoncteur du premier est ouvert, et la réponse
dégradée ne sert plus que si les deux sont tombés.

Deux garde-fous non négociables.

1. L'agent ne répond que sur ce qu'il a lu. Le contexte est constitué de passages
   réels du corpus ; s'il n'y en a pas, il le dit au lieu de composer une réponse
   plausible. C'est exactement le défaut que le corpus lui-même documente.
2. Le contexte respecte les droits. Sur les 71 ouvrages non redistribuables, les
   passages sont plafonnés avant d'atteindre le modèle : ce qui n'entre pas dans
   le contexte ne peut pas ressortir dans la réponse.
"""
import json
import logging

from app.core.auteurs import auteurs
from app.core.config import settings
from app.services import recherche
from app.services.droits import tronquer
from app.services.passages import extrait

log = logging.getLogger("ascenda.rag")

SYSTEME = """Tu es l'assistant de lecture d'ASCENDA. Tu réponds en français, à un
lecteur francophone, souvent africain, qui travaille un corpus d'ouvrages.

Règles absolues :
- Tu ne réponds qu'à partir des PASSAGES fournis. Ils sont numérotés.
- Chaque affirmation qui vient d'un passage porte sa marque : [1], [2]…
- Si les passages ne permettent pas de répondre, tu le dis franchement et tu
  proposes une reformulation ou un autre ouvrage. Tu ne combles jamais un trou
  par ce que tu crois savoir.
- Tu ne recopies pas de longs extraits : tu expliques, et tu cites brièvement.
- Quand les passages se contredisent, tu le signales au lieu de choisir.
- Ton : clair, adulte, sans flatterie ni jargon inutile. Pas de tiret cadratin.
"""


async def passages_pertinents(
    question: str,
    *,
    document_id: str | None = None,
    axe: str | None = None,
    limite: int = 8,
) -> list[dict]:
    """Le contexte de l'agent, cherché sur les mots et sur le sens.

    C'est ici que la recherche sémantique compte le plus : une question posée
    avec les mots de l'utilisateur ne reprend presque jamais ceux du livre.
    """
    lignes, _mode = await recherche.chercher(
        question, document_id=document_id, axe=axe, limite=limite
    )

    passages = []
    for i, l in enumerate(lignes, start=1):
        budget = 1800 if l["redistributable"] else min(700, int(l["max_excerpt_chars"] or 0))
        texte, coupe = tronquer(extrait(l["text"]), budget)
        if not texte:
            continue  # plafond à zéro : cet ouvrage ne peut rien fournir au contexte
        passages.append(
            {
                "n": len(passages) + 1,
                "chunk_id": str(l["id"]),
                "document_id": str(l["document_id"]),
                "ouvrage": l["ouvrage"],
                "auteurs": auteurs(l["authors"]),
                "chapitre_id": str(l["chapter_id"]) if l["chapter_id"] else None,
                "chapitre": l["chapitre"],
                "page": l["page_start"],
                "texte": texte,
                "tronque": coupe,
            }
        )
    return passages


def _contexte(passages: list[dict]) -> str:
    blocs = []
    for p in passages:
        entete = f"[{p['n']}] {p['ouvrage']}"
        if p["chapitre"]:
            entete += f", {p['chapitre']}"
        if p["page"]:
            entete += f", p. {p['page']}"
        blocs.append(f"{entete}\n{p['texte']}")
    return "\n\n".join(blocs)


async def repondre(
    question: str,
    passages: list[dict],
    historique: list[dict] | None = None,
) -> dict:
    """Retourne {reponse, tokens_in, tokens_out, degrade}.

    Sans clé d'API, on ne fabrique pas une réponse : on renvoie les passages
    trouvés en le disant. Une bibliothèque qui montre ses sources reste utile ;
    un assistant qui invente ne l'est pas.
    """
    if not passages:
        return {
            "reponse": (
                "Je ne trouve rien dans le corpus qui réponde à cette question. "
                "Essayez d'autres mots, ou précisez l'ouvrage : je ne réponds que "
                "sur ce que la bibliothèque contient réellement."
            ),
            "tokens_in": 0,
            "tokens_out": 0,
            "degrade": False,
            "modele": None,
        }

    from app.services import fournisseurs

    prets = await fournisseurs.actifs()
    if not prets:
        lignes = [
            f"[{p['n']}] {p['ouvrage']}" + (f", p. {p['page']}" if p["page"] else "")
            for p in passages
        ]
        return {
            "reponse": (
                "La rédaction automatique des réponses n'est pas activée sur cette "
                "installation. Voici les passages du corpus qui correspondent à votre "
                "question :\n\n" + "\n".join(lignes)
            ),
            "tokens_in": 0,
            "tokens_out": 0,
            "degrade": True,
            "modele": None,
        }

    messages = []
    for h in (historique or [])[-6:]:
        messages.append({"role": h["role"], "content": h["body"]})
    messages.append(
        {
            "role": "user",
            "content": f"PASSAGES\n\n{_contexte(passages)}\n\n---\n\nQUESTION\n{question}",
        }
    )

    from app.services.resilience import disjoncteur

    dernier = None
    for f in prets:
        appel = _APPELS[f["code"]]
        try:
            return await disjoncteur(f["code"]).appeler(appel, f, messages)
        except Exception as exc:  # noqa: BLE001
            dernier = exc
            log.warning("Fournisseur %s indisponible : %s", f["code"], exc)

    log.warning("Aucun fournisseur n'a répondu : %s", dernier)
    return {
        "reponse": (
            "L'assistant est momentanément indisponible. Les passages trouvés "
            "dans le corpus restent affichés sous cette réponse."
        ),
        "tokens_in": 0,
        "tokens_out": 0,
        "degrade": True,
        "modele": None,
    }


async def _anthropic(f: dict, messages: list[dict]) -> dict:
    from anthropic import AsyncAnthropic

    # 45 s au plus et une seule reprise : le client attend dix minutes par défaut,
    # et chaque question bloquée tient une connexion de l'API.
    client = AsyncAnthropic(api_key=f["cle"], timeout=45.0, max_retries=1)
    reponse = await client.messages.create(
        model=f["modele"],
        max_tokens=f["max_tokens"],
        system=SYSTEME,
        messages=messages,
    )
    texte = "".join(b.text for b in reponse.content if getattr(b, "type", "") == "text")
    return {
        "reponse": texte.strip(),
        "tokens_in": reponse.usage.input_tokens,
        "tokens_out": reponse.usage.output_tokens,
        "degrade": False,
        "modele": f["modele"],
    }


async def _openai(f: dict, messages: list[dict]) -> dict:
    """Appel direct en HTTP, sans SDK supplémentaire.

    Le client officiel embarquerait une dépendance de plus pour une seule
    requête, alors que `httpx` est déjà là pour Tara et Brevo. Les modèles
    récents refusent `max_tokens` et attendent `max_completion_tokens` : on
    envoie le nom que le modèle demandé accepte.
    """
    import httpx

    modele = f["modele"]
    recent = modele.startswith(("gpt-5", "o1", "o3", "o4"))
    corps = {
        "model": modele,
        "messages": [{"role": "system", "content": SYSTEME}, *messages],
        ("max_completion_tokens" if recent else "max_tokens"): f["max_tokens"],
    }
    async with httpx.AsyncClient(timeout=45.0) as client:
        r = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {f['cle']}"},
            json=corps,
        )
    if r.status_code >= 400:
        raise RuntimeError(f"OpenAI {r.status_code} : {r.text[:200]}")
    data = r.json()
    usage = data.get("usage") or {}
    return {
        "reponse": (data["choices"][0]["message"].get("content") or "").strip(),
        "tokens_in": int(usage.get("prompt_tokens") or 0),
        "tokens_out": int(usage.get("completion_tokens") or 0),
        "degrade": False,
        "modele": modele,
    }


_APPELS = {"anthropic": _anthropic, "openai": _openai}


def citations_utilisees(reponse: str, passages: list[dict]) -> list[dict]:
    """Ne renvoie au client que les passages effectivement cités.

    Afficher huit sources sous une réponse qui en utilise deux dilue la preuve.
    Si le modèle n'a marqué aucune référence, on renvoie tout : mieux vaut trop
    de sources que le soupçon d'une réponse sans source.
    """
    cites = {p["n"] for p in passages if f"[{p['n']}]" in reponse}
    retenus = [p for p in passages if p["n"] in cites] or passages
    return [
        {
            "chunk_id": p["chunk_id"],
            "document_id": p["document_id"],
            "ouvrage": p["ouvrage"],
            "auteurs": p["auteurs"],
            "chapitre_id": p["chapitre_id"],
            "chapitre": p["chapitre"],
            "page": p["page"],
            "extrait": p["texte"][:280],
            "marque": p["n"],
        }
        for p in retenus
    ]
