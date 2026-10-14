"""La console : régler l'agent, sa clé, son modèle et ce qu'il a le droit de coûter."""
from typing import Annotated, Literal

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import AdminUser
from app.core.errors import Conflict, NotFound
from app.services import fournisseurs

router = APIRouter(prefix="/admin", tags=["Administration"])


class FournisseurIn(BaseModel):
    modele: str | None = Field(default=None, min_length=2, max_length=80)
    actif: bool | None = None
    ordre: int | None = Field(default=None, ge=1, le=9)
    max_tokens_reponse: int | None = Field(default=None, ge=256, le=8000)
    # Écrite chiffrée, jamais relue. Une chaîne vide laisse la clé en place.
    cle: str | None = Field(default=None, max_length=300)


class QuotaIn(BaseModel):
    max_value: int | None = Field(default=None, ge=0, le=1_000_000_000)
    hard: bool | None = None


def _vue(f: dict) -> dict:
    return {
        "code": f["code"],
        "libelle": f["libelle"],
        "modele": f["modele"],
        "actif": f["actif"],
        "ordre": f["ordre"],
        "max_tokens_reponse": f["max_tokens_reponse"],
        "cle_posee": f["cle_posee"],
        "cle_indice": f["cle_indice"],
        "modifie_le": f["updated_at"],
    }


@router.get("/agent", summary="Le réglage de l'agent")
async def lire_agent(user: AdminUser):
    """Les fournisseurs et les plafonds de jetons, en un appel."""
    liste = await fournisseurs.tous()
    prets = [f["code"] for f in await fournisseurs.actifs()]
    plafonds = await fetch_all(
        """select plan, period, max_value, hard from plan_quota
            where type = 'agent_tokens' order by plan"""
    )
    return {
        "fournisseurs": [_vue(f) for f in liste],
        "prets": prets,
        "plafonds_jetons": [
            {"plan": p["plan"], "periode": p["period"], "limite": p["max_value"],
             "bloquant": p["hard"]}
            for p in plafonds
        ],
    }


@router.put("/agent/{code}", summary="Régler un fournisseur")
async def regler_agent(code: str, data: FournisseurIn, user: AdminUser):
    """Pose le modèle, la clé et l'ordre d'appel sans redéployer."""
    if code not in fournisseurs.CODES:
        raise NotFound("Ce fournisseur n'existe pas.")
    ligne = await fetch_one(
        "select cle_chiffree is not null as cle_posee from fournisseur_ia where code = %s",
        (code,),
    )
    if not ligne:
        raise NotFound("Ce fournisseur n'existe pas.")
    if data.actif and not ligne["cle_posee"] and not (data.cle or "").strip():
        raise Conflict("Posez d'abord une clé : sans clé, l'activation ne sert à rien.")
    champs = data.model_dump()
    return _vue(await fournisseurs.enregistrer(code, champs, par=str(user["id"])))


@router.delete("/agent/{code}/cle", status_code=204, summary="Retirer une clé")
async def retirer_cle(code: str, user: AdminUser):
    """Retire la clé et coupe le fournisseur, d'un seul geste."""
    if code not in fournisseurs.CODES:
        raise NotFound("Ce fournisseur n'existe pas.")
    await fournisseurs.retirer_cle(code)


@router.get("/quotas", summary="Les plafonds de toutes les formules")
async def lire_quotas(user: AdminUser):
    lignes = await fetch_all(
        "select plan, type, period, max_value, hard from plan_quota order by type, plan"
    )
    return [
        {"plan": l["plan"], "type": l["type"], "periode": l["period"],
         "limite": l["max_value"], "bloquant": l["hard"]}
        for l in lignes
    ]


@router.put("/quotas/{plan}/{type_}/{periode}", summary="Changer un plafond")
async def changer_quota(
    plan: str, type_: str, periode: Literal["day", "month", "total"],
    data: QuotaIn, user: AdminUser,
):
    """Change un plafond en base, sans redéploiement."""
    ligne = await fetch_one(
        "select 1 from plan_quota where plan = %s and type = %s and period = %s",
        (plan, type_, periode),
    )
    if not ligne:
        raise NotFound("Ce plafond n'existe pas.")
    champs = data.model_dump(exclude_unset=True)
    if not champs:
        raise Conflict("Rien à changer.")
    colonnes = ", ".join(f"{c} = %s" for c in champs)
    await execute(
        f"update plan_quota set {colonnes} where plan = %s and type = %s and period = %s",
        list(champs.values()) + [plan, type_, periode],
    )
    return {"plan": plan, "type": type_, "periode": periode, **champs}


@router.get("/agent/consommation", summary="Ce que l'agent a coûté")
async def consommation(user: AdminUser, jours: Annotated[int, Query(ge=1, le=365)] = 30):
    """Les jetons dépensés sur la période, en tout, par formule et par compte."""
    fenetre = "u.at >= now() - make_interval(days => %s)"
    total = await fetch_one(
        f"""select coalesce(sum(u.cost_tokens), 0) as jetons, count(*) as questions
              from usage_event u where u.type = 'agent_tokens' and {fenetre}""",
        (jours,),
    )
    par_plan = await fetch_all(
        f"""select a.plan, coalesce(sum(u.cost_tokens), 0) as jetons, count(*) as questions,
                   count(distinct u.user_id) as comptes
              from usage_event u join app_user a on a.id = u.user_id
             where u.type = 'agent_tokens' and {fenetre}
             group by a.plan order by jetons desc""",
        (jours,),
    )
    gros = await fetch_all(
        f"""select a.email, a.plan, coalesce(sum(u.cost_tokens), 0) as jetons,
                   count(*) as questions
              from usage_event u join app_user a on a.id = u.user_id
             where u.type = 'agent_tokens' and {fenetre}
             group by a.email, a.plan order by jetons desc limit 20""",
        (jours,),
    )
    return {
        "jours": jours,
        "jetons": int(total["jetons"]),
        "questions": int(total["questions"]),
        "par_formule": [
            {"plan": l["plan"], "jetons": int(l["jetons"]), "questions": int(l["questions"]),
             "comptes": int(l["comptes"])}
            for l in par_plan
        ],
        "plus_gros_usages": [
            {"email": l["email"], "plan": l["plan"], "jetons": int(l["jetons"]),
             "questions": int(l["questions"])}
            for l in gros
        ],
    }
