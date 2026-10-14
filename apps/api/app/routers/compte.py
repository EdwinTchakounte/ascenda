"""Compte : profil, compteurs d'usage, formule."""
from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import CurrentUser
from app.services import quotas

router = APIRouter(prefix="/compte", tags=["Compte"])


class ProfilIn(BaseModel):
    nom: str | None = Field(default=None, max_length=120)
    minutes_semaine: int | None = Field(default=None, ge=15, le=2000)
    vitesse_lecture_wpm: int | None = Field(default=None, ge=80, le=800)
    objectif: str | None = None
    langue: str | None = Field(default=None, max_length=8)


@router.get("", summary="Votre compte")
async def compte(user: CurrentUser):
    profil = await fetch_one("select * from user_profile where user_id = %s", (user["id"],))
    abonnement = await fetch_one(
        """select plan, status, current_start, current_end, amount_cents, currency, provider
           from subscription where user_id = %s
           order by current_end desc nulls last limit 1""",
        (user["id"],),
    )
    axes = await fetch_all(
        """select a.slug, a.label, ua.goal, ua.status, ua.target_date
           from user_axis ua join axis a on a.id = ua.axis_id
           where ua.user_id = %s order by ua.created_at desc""",
        (user["id"],),
    )
    return {
        "id": str(user["id"]),
        "email": user["email"],
        "nom": user["display_name"],
        "plan": user["plan"],
        "plan_jusqu_au": user["plan_until"],
        "inscrit_le": user["created_at"],
        "profil": (
            {
                "niveau": profil["level_assessed"],
                "evalue_le": profil["assessed_at"],
                "objectif": profil["goal"],
                "minutes_semaine": profil["weekly_minutes"],
                "vitesse_lecture_wpm": profil["reading_speed_wpm"],
                "langue": profil["language"],
            }
            if profil
            else None
        ),
        "abonnement": (
            {
                "plan": abonnement["plan"],
                "statut": abonnement["status"],
                "debut": abonnement["current_start"],
                "fin": abonnement["current_end"],
                "montant_centimes": abonnement["amount_cents"],
                "devise": abonnement["currency"],
                "fournisseur": abonnement["provider"],
            }
            if abonnement
            else None
        ),
        "axes": [
            {
                "slug": a["slug"],
                "label": a["label"],
                "objectif": a["goal"],
                "statut": a["status"],
                "echeance": a["target_date"],
            }
            for a in axes
        ],
    }


@router.patch("", summary="Modifier votre profil")
async def modifier(data: ProfilIn, user: CurrentUser):
    if data.nom is not None:
        await execute("update app_user set display_name = %s where id = %s", (data.nom, user["id"]))
    if data.langue:
        await execute("update app_user set locale = %s where id = %s", (data.langue, user["id"]))
    if any(v is not None for v in (data.minutes_semaine, data.vitesse_lecture_wpm, data.objectif, data.langue)):
        await execute(
            """insert into user_profile (user_id, weekly_minutes, reading_speed_wpm, goal, language)
               values (%s, %s, %s, %s, coalesce(%s, 'fr'))
               on conflict (user_id) do update set
                 weekly_minutes    = coalesce(excluded.weekly_minutes, user_profile.weekly_minutes),
                 reading_speed_wpm = coalesce(excluded.reading_speed_wpm, user_profile.reading_speed_wpm),
                 goal              = coalesce(excluded.goal, user_profile.goal),
                 language          = coalesce(excluded.language, user_profile.language)""",
            (user["id"], data.minutes_semaine, data.vitesse_lecture_wpm, data.objectif, data.langue),
        )
    return await compte(user)


@router.get("/usage", summary="Vos compteurs")
async def usage(user: CurrentUser):
    compteurs = await quotas.summary(user)
    couts = await fetch_one(
        """select coalesce(sum(cost_tokens), 0) as tokens
           from usage_event where user_id = %s and at >= date_trunc('month', now())""",
        (user["id"],),
    )
    return {
        "plan": user["plan"],
        "compteurs": compteurs,
        "tokens_du_mois": int(couts["tokens"] or 0),
    }


@router.get("/formules", summary="Les formules disponibles")
async def formules():
    """Lues depuis plan_quota : la page de tarifs ne peut pas diverger du code
    qui applique les limites."""
    lignes = await fetch_all(
        "select plan, type, period, max_value, hard from plan_quota order by plan, type"
    )
    # La formule la moins chère : c'est le prix d'appel, celui qu'on affiche à
    # côté du nom de l'offre.
    tarif = await fetch_one(
        """select montant, devise, periode_mois from plan_tarif
            where plan = 'premium' and actif order by montant limit 1"""
    )
    par_plan: dict[str, list] = {}
    for l in lignes:
        par_plan.setdefault(l["plan"], []).append(
            {
                "type": l["type"],
                "periode": l["period"],
                "limite": l["max_value"],
                "bloquant": l["hard"],
            }
        )
    return [
        {
            "code": "free",
            "nom": "Découverte",
            "prix": 0,
            "devise": (tarif or {}).get("devise", "XAF"),
            "periode_mois": None,
            "resume": "La bibliothèque de base, un axe, un chronogramme, les quiz déjà préparés.",
            "limites": par_plan.get("free", []),
        },
        {
            "code": "premium",
            "nom": "Ascension",
            "prix": (tarif or {}).get("montant"),
            "devise": (tarif or {}).get("devise", "XAF"),
            "periode_mois": (tarif or {}).get("periode_mois"),
            "resume": "Vos propres documents, axes illimités, chronogramme adaptatif, "
                      "synthèses et quiz à la demande, export.",
            "limites": par_plan.get("premium", []),
        },
    ]
