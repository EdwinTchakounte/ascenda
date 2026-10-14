"""Ce qu'un lecteur peut faire, en un seul endroit."""
from datetime import datetime, timezone

from app.core.db import fetch_all

# Le catalogue des fonctions qu'un code limité peut ouvrir. La clé est stable,
# le libellé est ce que voient le lecteur et la console.
FONCTIONS: dict[str, str] = {
    "agent_question": "Questions à l'agent sans compter",
    "quiz_generated": "Quiz à la demande",
    "synthesis_generated": "Synthèses à la demande",
    "export_pdf": "Export PDF",
    "chronogram_active": "Plusieurs chronogrammes à la fois",
    "chronogramme_adaptatif": "Chronogramme adaptatif et replanification",
    "doc_uploaded": "Import de vos propres documents",
    "axes_reserves": "Parcours réservés à Ascension",
    "lecture_application": "Lecture intégrale et hors ligne des ouvrages réservés",
}

# Un compteur de quota qui n'a pas sa propre entrée au catalogue suit celle dont
# il dépend : le traitement des scans ne sert à rien sans l'import.
_COMPTEUR_VERS_FONCTION = {"ocr_pages": "doc_uploaded", "agent_tokens": "agent_question"}


def fonction_du_compteur(compteur: str) -> str:
    return _COMPTEUR_VERS_FONCTION.get(compteur, compteur)


async def codes_actifs(user_id: str) -> list[dict]:
    """Les accès en cours ouverts par un code, du plus large au plus court."""
    lignes = await fetch_all(
        """select c.code, c.libelle, c.niveau, c.fonctions, u.active_le,
                  least(u.fin, c.fin) as fin
             from code_acces_utilisation u join code_acces c on c.id = u.code_id
            where u.user_id = %s and c.actif
              and least(u.fin, c.fin) > now()
            order by (c.niveau = 'complet') desc, least(u.fin, c.fin) desc""",
        (user_id,),
    )
    maintenant = datetime.now(timezone.utc)
    return [
        {
            "code": l["code"],
            "libelle": l["libelle"],
            "niveau": l["niveau"],
            "fonctions": list(FONCTIONS) if l["niveau"] == "complet"
                         else [f for f in (l["fonctions"] or []) if f in FONCTIONS],
            "active_le": l["active_le"],
            "fin": l["fin"],
            "jours_restants": max(0, (l["fin"] - maintenant).days),
        }
        for l in lignes
    ]


async def etat(user: dict) -> dict:
    """L'accès effectif, tel que l'application doit l'afficher."""
    from app.services import exploitation

    if user.get("plan") and user["plan"] != "free":
        return {"complet": True, "fonctions": list(FONCTIONS), "source": "abonnement",
                "jusqu_au": user.get("plan_until"), "codes": await codes_actifs(str(user["id"]))}

    lancement = await exploitation.lancement()
    codes = await codes_actifs(str(user["id"]))
    if lancement["actif"]:
        return {"complet": True, "fonctions": list(FONCTIONS), "source": "lancement",
                "jusqu_au": lancement.get("jusqu_au"), "codes": codes}

    complets = [c for c in codes if c["niveau"] == "complet"]
    if complets:
        return {"complet": True, "fonctions": list(FONCTIONS), "source": "code",
                "jusqu_au": max(c["fin"] for c in complets), "codes": codes}

    ouvertes = sorted({f for c in codes for f in c["fonctions"]}, key=list(FONCTIONS).index)
    return {
        "complet": False,
        "fonctions": ouvertes,
        "source": "code" if ouvertes else "aucune",
        "jusqu_au": max((c["fin"] for c in codes), default=None),
        "codes": codes,
    }


async def a_droit(user: dict, fonction: str) -> bool:
    e = await etat(user)
    return e["complet"] or fonction_du_compteur(fonction) in e["fonctions"]


async def plafond_jetons(user_id: str) -> dict | None:
    """Le plafond de jetons porté par un code d'accès, s'il y en a un."""
    lignes = await fetch_all(
        """select c.code, c.plafond_tokens, u.active_le
             from code_acces_utilisation u join code_acces c on c.id = u.code_id
            where u.user_id = %s and c.actif and c.plafond_tokens is not null
              and least(u.fin, c.fin) > now()
            order by c.plafond_tokens""",
        (user_id,),
    )
    if not lignes:
        return None
    l = lignes[0]
    return {"code": l["code"], "plafond": int(l["plafond_tokens"]), "depuis": l["active_le"]}


async def plan_pour(user: dict, compteur: str) -> str:
    """Le plan dont on applique les plafonds pour ce compteur précis."""
    return "premium" if await a_droit(user, compteur) else user["plan"]
