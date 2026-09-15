"""Lecteur : le texte servi passage par passage, sous contrôle de droits.

Pour les 7 ouvrages redistribuables, le chapitre est rendu en entier. Pour les
71 autres, le lecteur reçoit des extraits plafonnés et un message qui explique
pourquoi, plutôt qu'une page vide sans raison.
"""
from typing import Annotated

from fastapi import APIRouter, Query

from app.core.auteurs import auteurs
from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import CurrentUser, OptionalUser
from app.core.errors import Forbidden, NotFound
from app.services.droits import droits, repartir
from app.services.passages import lisibles

router = APIRouter(prefix="/lecteur", tags=["Lecteur"])


async def _precedent(document_id: str, passages: list[dict]) -> str | None:
    """Le passage qui précède le premier : sa fin est reprise au début de celui-ci."""
    if not passages:
        return None
    ligne = await fetch_one(
        "select text from chunk where document_id = %s and ord = %s", (document_id, passages[0]["ord"] - 1))
    return ligne["text"] if ligne else None


def _rendu(passages: list[dict], budget: int, precedent: str | None = None) -> tuple[list[dict], bool]:
    # Le nettoyage passe avant le plafond de droits : la reprise d'un passage sur
    # l'autre ne doit pas consommer le budget d'extrait.
    propres = lisibles([p["text"] for p in passages], precedent)
    # Un passage qui n'était que la reprise du précédent n'a plus rien à dire.
    gardes = [(p, t) for p, t in zip(passages, propres) if t.strip()]
    passages, propres = [p for p, _ in gardes], [t for _, t in gardes]
    textes = repartir(budget, propres)
    tronque = False
    sortie = []
    precedent_coupe = False
    for p, t, propre in zip(passages, textes, propres):
        coupe = len(t) < len(propre)
        tronque = tronque or coupe
        # Après un extrait abrégé, le passage suivant reprend en cours de phrase :
        # on le signale plutôt que de laisser croire à une coquille.
        if t and precedent_coupe and t[:1].islower():
            t = f"…{t}"
        precedent_coupe = coupe
        sortie.append(
            {
                "id": str(p["id"]),
                "ordre": p["ord"],
                "page_debut": p["page_start"],
                "page_fin": p["page_end"],
                "texte": t,
                "tronque": coupe,
                "tokens": p["token_count"],
            }
        )
    return sortie, tronque


@router.get("/{document_id}/chapitre/{chapter_id}", summary="Le texte d'un chapitre")
async def chapitre(document_id: str, chapter_id: str, user: OptionalUser):
    ch = await fetch_one(
        """select c.id, c.ord, c.title, c.page_start, c.page_end, c.token_count,
                  d.id as doc_id, coalesce(d.title_clean, d.title_raw) as doc_titre, d.authors,
                  case when coalesce(d.mime, 'application/pdf') = 'application/pdf' then d.storage_key end as storage_key
           from chapter c join document d on d.id = c.document_id
           where c.id = %s and c.document_id = %s""",
        (chapter_id, document_id),
    )
    if not ch:
        raise NotFound("Ce chapitre n'existe pas dans cet ouvrage.")

    dr = await droits(document_id)
    passages = await fetch_all(
        """select id, ord, page_start, page_end, text, token_count
           from chunk where chapter_id = %s order by ord""",
        (chapter_id,),
    )
    rendus, tronque = _rendu(passages, dr.budget(), await _precedent(document_id, passages))

    voisins = await fetch_all(
        """select id, ord, title from chapter
           where document_id = %s and ord in (%s, %s)""",
        (document_id, (ch["ord"] or 0) - 1, (ch["ord"] or 0) + 1),
    )
    prec = next((v for v in voisins if v["ord"] == (ch["ord"] or 0) - 1), None)
    suiv = next((v for v in voisins if v["ord"] == (ch["ord"] or 0) + 1), None)

    # Le compte rendu voyage avec le chapitre plutôt que dans un appel à part :
    # sur une connexion mobile, un aller-retour de moins vaut mieux qu'une
    # charge utile un peu plus grosse. Il est nul tant qu'il n'a pas été produit,
    # et l'application ne montre alors simplement rien.
    cr = await fetch_one(
        """select content from derivative
            where chapter_id = %s and kind = 'compte_rendu' and superseded_by is null
            order by generated_at desc limit 1""",
        (chapter_id,),
    )

    return {
        "ouvrage": {"id": str(ch["doc_id"]), "titre": ch["doc_titre"], "auteurs": auteurs(ch["authors"])},
        "chapitre": {
            "id": str(ch["id"]),
            "ordre": ch["ord"],
            "titre": ch["title"],
            "page_debut": ch["page_start"],
            "page_fin": ch["page_end"],
            "duree_min": max(1, round((ch["token_count"] or 0) * 0.75 / 200)) if ch["token_count"] else None,
        },
        "passages": rendus,
        "droits": {
            "lecture_integrale": dr.texte_integral,
            # Le PDF d'origine s'ouvre à la page du chapitre, sous la même règle.
            "pdf": dr.texte_integral and bool(ch["storage_key"]),
            "tronque": tronque,
            "message": dr.message(),
        },
        # Notre texte, pas celui de l'auteur : un compte rendu est une oeuvre
        # dérivée que nous écrivons. Il n'est donc pas soumis au plafond de
        # citation, qui ne gouverne que les extraits littéraux.
        "compte_rendu": (cr or {}).get("content"),
        "precedent": {"id": str(prec["id"]), "titre": prec["title"]} if prec else None,
        "suivant": {"id": str(suiv["id"]), "titre": suiv["title"]} if suiv else None,
    }


@router.get("/{document_id}/pages", summary="Le texte d'une plage de pages")
async def pages(
    document_id: str,
    user: OptionalUser,
    debut: Annotated[int, Query(ge=1)] = 1,
    fin: Annotated[int | None, Query(ge=1)] = None,
):
    dr = await droits(document_id)
    fin = fin or debut + 9
    passages = await fetch_all(
        """select id, ord, page_start, page_end, text, token_count
           from chunk
           where document_id = %s and page_end >= %s and page_start <= %s
           order by ord""",
        (document_id, debut, fin),
    )
    if not passages:
        raise NotFound("Aucun passage pour cette plage de pages.")
    rendus, tronque = _rendu(passages, dr.budget(), await _precedent(document_id, passages))
    return {
        "document_id": document_id,
        "page_debut": debut,
        "page_fin": fin,
        "passages": rendus,
        "droits": {"lecture_integrale": dr.texte_integral, "tronque": tronque, "message": dr.message()},
    }


@router.get("/{document_id}/citations", summary="Les citations retenues d'un ouvrage")
async def citations(
    document_id: str,
    user: OptionalUser,
    chapitre_id: Annotated[str | None, Query()] = None,
    axe: Annotated[str | None, Query()] = None,
):
    """Les citations sont déjà courtes et vérifiées mot à mot contre le texte source :
    elles sont servables même sur un ouvrage non redistribuable."""
    params: list = [document_id]
    where = "dv.document_id = %s and dv.kind = 'citation' and dv.superseded_by is null"
    if chapitre_id:
        where += " and dv.chapter_id = %s"
        params.append(chapitre_id)
    lignes = await fetch_all(
        f"""select dv.chapter_id, c.title as chapitre, c.ord, dv.content
            from derivative dv left join chapter c on c.id = dv.chapter_id
            where {where} order by c.ord nulls last""",
        params,
    )
    sortie = []
    for l in lignes:
        for cit in (l["content"] or {}).get("citations", []):
            if axe and cit.get("axe") != axe:
                continue
            sortie.append(
                {
                    "chapitre_id": str(l["chapter_id"]) if l["chapter_id"] else None,
                    "chapitre": l["chapitre"],
                    "texte": cit.get("texte"),
                    "page": cit.get("page"),
                    "axe": cit.get("axe"),
                    "theme": cit.get("theme"),
                    "portee": cit.get("portee"),
                }
            )
    return {"document_id": document_id, "total": len(sortie), "citations": sortie}


@router.post("/{document_id}/ouvert", status_code=204, summary="Signaler l'ouverture d'un ouvrage")
async def signaler_ouverture(document_id: str, user: CurrentUser):
    """Alimente le journal de progression, qui rend le chronogramme adaptatif."""
    await execute(
        """insert into progress_event (user_id, document_id, type, payload)
           values (%s, %s, 'opened_doc', '{}'::jsonb)""",
        (user["id"], document_id),
    )


@router.get("/{document_id}/pdf", summary="Le PDF d'un ouvrage redistribuable")
async def pdf(document_id: str, user: OptionalUser):
    """Le fichier tel qu'il a été publié, pour le lire page par page.

    Seulement pour les ouvrages dont le texte intégral peut être servi : le PDF
    d'une œuvre protégée, c'est l'œuvre entière, et la règle de `droits.py`
    vaut ici comme partout. Les autres ouvrages restent lisibles par extraits.
    """
    dr = await droits(document_id)
    if not dr.texte_integral:
        raise Forbidden(
            dr.message() or "Le PDF de cet ouvrage ne peut pas être affiché ici."
        )
    d = await fetch_one(
        """select storage_key, filename_original, mime, size_bytes,
                  coalesce(title_clean, title_raw) as titre
             from document where id = %s""",
        (document_id,),
    )
    if not d or not d["storage_key"] or (d["mime"] or "application/pdf") != "application/pdf":
        raise NotFound("Cet ouvrage n'a pas de PDF à afficher.")
    from app.services import stockage

    return stockage.servir(
        d["storage_key"], nom=f"{d['titre']}.pdf", mime="application/pdf"
    )
