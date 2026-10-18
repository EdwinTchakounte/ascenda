"""La console : créer les codes d'accès, suivre les ambassadeurs."""
from datetime import datetime, timezone
from typing import Annotated, Literal

from fastapi import APIRouter, Query, status
from pydantic import BaseModel, Field, field_validator

from app.core.db import fetch_all, fetch_one
from app.core.deps import AdminUser
from app.core.errors import Conflict, NotFound
from app.routers.admin import PAR_PAGE, bornes, enveloppe
from app.services import acces, exploitation
from app.services.codes import CodeRefuse, normaliser

router = APIRouter(prefix="/admin", tags=["Administration"])

_FORME = r"^[A-Z0-9][A-Z0-9-]{2,30}[A-Z0-9]$"


class CodeIn(BaseModel):
    code: str = Field(min_length=4, max_length=32)
    libelle: str = Field(min_length=2, max_length=120)
    niveau: Literal["complet", "limite"]
    fonctions: list[str] = []
    debut: datetime | None = None
    fin: datetime
    duree_jours: int | None = Field(default=None, gt=0, le=3650)
    max_utilisations: int | None = Field(default=None, gt=0)
    # Le coût total que ce code s'autorise, compté depuis chaque activation.
    plafond_tokens: int | None = Field(default=None, gt=0, le=1_000_000_000)

    @field_validator("code")
    @classmethod
    def _code(cls, v: str) -> str:
        return normaliser(v)


class CodeChangeIn(BaseModel):
    libelle: str | None = Field(default=None, min_length=2, max_length=120)
    actif: bool | None = None
    fin: datetime | None = None
    max_utilisations: int | None = Field(default=None, gt=0)
    plafond_tokens: int | None = Field(default=None, gt=0, le=1_000_000_000)


def _utc(d: datetime) -> datetime:
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def _statut(c: dict) -> str:
    maintenant = datetime.now(timezone.utc)
    if not c["actif"]:
        return "desactive"
    if c["fin"] <= maintenant:
        return "expire"
    if c["debut"] > maintenant:
        return "programme"
    if c["max_utilisations"] and c["utilisations"] >= c["max_utilisations"]:
        return "epuise"
    return "actif"


def _vue(c: dict) -> dict:
    return {
        "id": str(c["id"]),
        "code": c["code"],
        "libelle": c["libelle"],
        "niveau": c["niveau"],
        "fonctions": list(acces.FONCTIONS) if c["niveau"] == "complet" else list(c["fonctions"] or []),
        "debut": c["debut"],
        "fin": c["fin"],
        "duree_jours": c["duree_jours"],
        "max_utilisations": c["max_utilisations"],
        "plafond_tokens": c["plafond_tokens"],
        "utilisations": c["utilisations"],
        "en_cours": c["en_cours"],
        "actif": c["actif"],
        "statut": _statut(c),
        "cree_le": c["created_at"],
    }


_SELECT = """select c.*,
       (select count(*) from code_acces_utilisation u where u.code_id = c.id) as utilisations,
       (select count(*) from code_acces_utilisation u
         where u.code_id = c.id and least(u.fin, c.fin) > now()) as en_cours
  from code_acces c"""


@router.get("/codes", summary="Les codes d'accès")
async def lister(
    user: AdminUser,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    total = await fetch_one("select count(*) as n from code_acces")
    limite, saut = bornes(page, par_page)
    lignes = await fetch_all(_SELECT + " order by c.created_at desc limit %s offset %s", (limite, saut))
    return {
        **enveloppe([_vue(c) for c in lignes], total["n"], page, par_page),
        "fonctions": [{"cle": k, "libelle": v} for k, v in acces.FONCTIONS.items()],
    }


@router.post("/codes", status_code=status.HTTP_201_CREATED, summary="Créer un code d'accès")
async def creer(data: CodeIn, user: AdminUser):
    import re

    if not re.match(_FORME, data.code):
        raise CodeRefuse("Un code s'écrit en lettres et chiffres, tirets permis au milieu, "
                         "de 4 à 32 caractères.")
    debut = _utc(data.debut) if data.debut else datetime.now(timezone.utc)
    fin = _utc(data.fin)
    if fin <= datetime.now(timezone.utc) or fin <= debut:
        raise CodeRefuse("La date de fin doit être dans le futur, et après le début.")
    fonctions = sorted(set(data.fonctions)) if data.niveau == "limite" else []
    inconnues = [f for f in fonctions if f not in acces.FONCTIONS]
    if inconnues:
        raise CodeRefuse(f"Fonctions inconnues : {', '.join(inconnues)}.")
    if data.niveau == "limite" and not fonctions:
        raise CodeRefuse("Un code limité ouvre au moins une fonction.")
    if await fetch_one("select 1 from app_user where code_parrainage = %s", (data.code,)):
        raise Conflict("Ce code est déjà le code ambassadeur d'un lecteur.")
    if await fetch_one("select 1 from code_acces where code = %s", (data.code,)):
        raise Conflict("Ce code existe déjà.")
    cree = await fetch_one(
        """insert into code_acces (code, libelle, niveau, fonctions, debut, fin, duree_jours,
                                   max_utilisations, plafond_tokens, cree_par)
           values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) returning id""",
        (data.code, data.libelle.strip(), data.niveau, fonctions, debut, fin,
         data.duree_jours, data.max_utilisations, data.plafond_tokens, user["id"]),
    )
    return _vue(await fetch_one(_SELECT + " where c.id = %s", (cree["id"],)))


@router.get("/codes/{code_id}", summary="Un code et ceux qui l'ont utilisé")
async def un_code(code_id: str, user: AdminUser):
    c = await fetch_one(_SELECT + " where c.id = %s", (code_id,))
    if not c:
        raise NotFound("Ce code n'existe pas.")
    utilisations = await fetch_all(
        """select a.email, u.active_le, least(u.fin, c.fin) as fin, u.origine
             from code_acces_utilisation u
             join app_user a on a.id = u.user_id
             join code_acces c on c.id = u.code_id
            where u.code_id = %s order by u.active_le desc limit 500""",
        (code_id,),
    )
    return {**_vue(c), "utilisateurs": [
        {"email": u["email"], "active_le": u["active_le"], "fin": u["fin"], "origine": u["origine"],
         "en_cours": u["fin"] > datetime.now(timezone.utc)}
        for u in utilisations
    ]}


@router.patch("/codes/{code_id}", summary="Désactiver, prolonger ou renommer un code")
async def changer(code_id: str, data: CodeChangeIn, user: AdminUser):
    """Désactiver un code referme aussitôt les accès qu'il avait ouverts."""
    c = await fetch_one("select * from code_acces where id = %s", (code_id,))
    if not c:
        raise NotFound("Ce code n'existe pas.")
    champs = data.model_dump(exclude_none=True)
    if "fin" in champs:
        champs["fin"] = _utc(champs["fin"])
        if champs["fin"] <= c["debut"]:
            raise CodeRefuse("La date de fin doit venir après le début.")
    if not champs:
        raise NotFound("Rien à changer.")
    colonnes = ", ".join(f"{k} = %s" for k in champs)
    await fetch_one(
        f"update code_acces set {colonnes}, updated_at = now() where id = %s returning id",
        list(champs.values()) + [code_id],
    )
    return _vue(await fetch_one(_SELECT + " where c.id = %s", (code_id,)))


@router.get("/ambassadeurs", summary="Le programme ambassadeur")
async def ambassadeurs(
    user: AdminUser,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    """Qui fait venir des lecteurs, et ce que cela coûte en réductions."""
    reglage = await exploitation.parrainage()
    totaux = await fetch_one(
        """select (select count(*) from app_user where parrain_id is not null) as filleuls,
                  (select count(distinct parrain_id) from app_user where parrain_id is not null) as ambassadeurs,
                  (select count(*) from bon_reduction) as bons,
                  (select count(*) from bon_reduction where utilise_le is not null) as bons_utilises,
                  (select coalesce(sum(p.montant_brut - p.montant), 0) from payment p
                    where p.bon_id is not null and p.statut = 'valide') as remises_accordees"""
    )
    total = await fetch_one(
        "select count(distinct parrain_id) as n from app_user where parrain_id is not null")
    limite, saut = bornes(page, par_page)
    lignes = await fetch_all(
        """select a.id, a.email, a.code_parrainage, count(f.id) as filleuls,
                  (select count(*) from bon_reduction b where b.user_id = a.id and b.utilise_le is not null) as bons_utilises,
                  (select count(*) from bon_reduction b where b.user_id = a.id and b.utilise_le is null
                      and b.expire_le > now()) as bons_disponibles,
                  max(f.created_at) as dernier
             from app_user a join app_user f on f.parrain_id = a.id
            group by a.id order by count(f.id) desc, max(f.created_at) desc
            limit %s offset %s""",
        (limite, saut),
    )
    return {
        **enveloppe([
            {"id": str(l["id"]), "email": l["email"], "code": l["code_parrainage"],
             "filleuls": l["filleuls"], "bons_disponibles": l["bons_disponibles"],
             "bons_utilises": l["bons_utilises"], "dernier": l["dernier"]}
            for l in lignes
        ], total["n"], page, par_page),
        "reglage": reglage,
        "totaux": totaux,
    }
