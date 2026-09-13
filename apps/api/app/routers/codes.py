"""Codes d'accès, code ambassadeur et réductions, côté lecteur."""
from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import CurrentUser
from app.services import acces, codes, exploitation

router = APIRouter(prefix="/codes", tags=["Codes et avantages"])


class ActiverIn(BaseModel):
    code: str = Field(min_length=3, max_length=40)


def _prenom(nom: str | None) -> str | None:
    return ((nom or "").strip().split(" ") or [""])[0] or None


@router.get("/moi", summary="Vos codes, vos accès et vos réductions")
async def mes_codes(user: CurrentUser):
    """Tout ce que l'écran « Codes et avantages » affiche, en un appel.

    `nouveaux` compte les réductions gagnées que l'application n'a pas encore
    montrées : c'est la notification dans l'application, le courriel étant
    l'autre moitié.
    """
    code = await codes.code_ambassadeur(user)
    reglage = await exploitation.parrainage()
    bons = await fetch_all(
        """select b.id, b.pourcent, b.expire_le, b.utilise_le, b.vu_le, b.created_at,
                  f.display_name as filleul
             from bon_reduction b left join app_user f on f.id = b.filleul_id
            where b.user_id = %s order by b.created_at desc""",
        (user["id"],),
    )
    filleuls = await fetch_one("select count(*) as n from app_user where parrain_id = %s", (user["id"],))
    disponible = await codes.bon_disponible(str(user["id"]))
    etat = await acces.etat(user)

    def statut(b: dict) -> str:
        if b["utilise_le"]:
            return "utilise"
        from datetime import datetime, timezone

        return "expire" if b["expire_le"] <= datetime.now(timezone.utc) else "disponible"

    return {
        "ambassadeur": {
            "code": code,
            "actif": reglage["actif"],
            "pourcent": reglage["pourcent"],
            "validite_jours": reglage["validite_jours"],
            "filleuls": filleuls["n"],
            "message_partage": (
                f"Je lis avec ASCENDA, qui transforme une bibliothèque en plan de lecture. "
                f"Crée ton compte avec mon code {code}."
            ),
        },
        "acces": etat,
        "reduction_prochaine": {"pourcent": disponible["pourcent"], "expire_le": disponible["expire_le"]}
        if disponible else None,
        "bons": [
            {
                "id": str(b["id"]),
                "pourcent": b["pourcent"],
                "statut": statut(b),
                "expire_le": b["expire_le"],
                "utilise_le": b["utilise_le"],
                "gagne_le": b["created_at"],
                "filleul": _prenom(b["filleul"]),
                "nouveau": b["vu_le"] is None,
            }
            for b in bons
        ],
        "nouveaux": sum(1 for b in bons if b["vu_le"] is None),
        "fonctions": [{"cle": k, "libelle": v} for k, v in acces.FONCTIONS.items()],
    }


@router.post("/activer", summary="Activer un code d'accès")
async def activer(data: ActiverIn, user: CurrentUser):
    resultat = await codes.activer_acces(user, data.code, "compte")
    return {**resultat, "acces": await acces.etat(user)}


@router.post("/bons/vus", status_code=204, summary="Marquer les réductions comme vues")
async def bons_vus(user: CurrentUser):
    await execute("update bon_reduction set vu_le = now() where user_id = %s and vu_le is null",
                  (user["id"],))
