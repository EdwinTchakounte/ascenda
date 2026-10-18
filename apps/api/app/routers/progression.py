"""Progression : ce que le journal append-only permet de dire."""
from typing import Annotated

from fastapi import APIRouter, Query

from app.core.db import fetch_all, fetch_one
from app.core.deps import CurrentUser

router = APIRouter(prefix="/progression", tags=["Progression"])


@router.get("", summary="Vue d'ensemble")
async def vue_ensemble(user: CurrentUser):
    seances = await fetch_one(
        """select count(*) as total,
                  count(*) filter (where s.status = 'fait') as faites,
                  count(*) filter (where s.status = 'a_venir'
                                 and s.planned_at::date < current_date) as en_retard,
                  coalesce(sum(s.actual_duration_min) filter (where s.status = 'fait'), 0) as minutes
           from session s
           join chronogram c on c.id = s.chronogram_id
           join user_axis ua on ua.id = c.user_axis_id
           where ua.user_id = %s and c.status = 'actif'""",
        (user["id"],),
    )
    quiz = await fetch_one(
        """select count(*) as tentatives,
                  round(avg((payload->>'score')::numeric), 3) as score_moyen
           from progress_event where user_id = %s and type = 'quiz_attempt'""",
        (user["id"],),
    )
    ouvrages = await fetch_one(
        """select count(distinct s.document_id) as commences,
                  count(distinct s.document_id) filter (where fini.reste = 0) as termines
           from session s
           join chronogram c on c.id = s.chronogram_id
           join user_axis ua on ua.id = c.user_axis_id
           left join lateral (
             select count(*) filter (where s2.status <> 'fait') as reste
             from session s2 where s2.chronogram_id = s.chronogram_id
               and s2.document_id = s.document_id
           ) fini on true
           where ua.user_id = %s""",
        (user["id"],),
    )
    notions = await fetch_one(
        """select count(*) as suivies,
                  count(*) filter (where repetitions >= 3) as maitrisees,
                  count(*) filter (where next_review_at is null or next_review_at <= now()) as a_revoir
           from concept_mastery where user_id = %s""",
        (user["id"],),
    )
    return {
        "seances": {
            "total": seances["total"],
            "faites": seances["faites"],
            "en_retard": seances["en_retard"],
            "minutes_lues": int(seances["minutes"] or 0),
            "avancement": round(seances["faites"] / seances["total"], 3) if seances["total"] else 0.0,
        },
        "quiz": {
            "tentatives": quiz["tentatives"],
            "score_moyen": float(quiz["score_moyen"]) if quiz["score_moyen"] is not None else None,
        },
        "ouvrages": {"commences": ouvrages["commences"], "termines": ouvrages["termines"]},
        "notions": {
            "suivies": notions["suivies"],
            "maitrisees": notions["maitrisees"],
            "a_revoir": notions["a_revoir"],
        },
    }


@router.get("/regularite", summary="Courbe de régularité")
async def regularite(user: CurrentUser, jours: Annotated[int, Query(ge=7, le=365)] = 84):
    """Un point par jour sur la période, y compris les jours sans activité."""
    lignes = await fetch_all(
        """with jours as (
             select generate_series(current_date - %s::int, current_date, '1 day')::date as j
           )
           select j.j as jour,
                  count(pe.id) filter (where pe.type in ('read_pages','quiz_attempt')) as actions,
                  coalesce(sum((pe.payload->>'duree_min')::int)
                           filter (where pe.type = 'read_pages'), 0) as minutes
           from jours j
           left join progress_event pe
             on date(pe.at) = j.j and pe.user_id = %s
           group by j.j order by j.j""",
        (jours, user["id"]),
    )
    points = [
        {"jour": l["jour"], "actions": l["actions"], "minutes": int(l["minutes"] or 0)}
        for l in lignes
    ]
    # Série en cours : nombre de jours consécutifs actifs jusqu'à aujourd'hui.
    serie = 0
    for p in reversed(points):
        if p["actions"] > 0:
            serie += 1
        elif serie or p is points[-1]:
            break
    return {
        "jours": jours,
        "serie_en_cours": serie,
        "jours_actifs": sum(1 for p in points if p["actions"] > 0),
        "points": points,
    }


@router.get("/maitrise", summary="Carte de maîtrise des notions")
async def maitrise(user: CurrentUser, limite: Annotated[int, Query(le=300)] = 120):
    lignes = await fetch_all(
        """select c.id, c.term, cm.ease, cm.repetitions, cm.interval_days, cm.next_review_at,
                  a.slug as axe, a.label as axe_label
           from concept_mastery cm
           join concept c on c.id = cm.concept_id
           left join axis a on a.id = c.axis_id
           where cm.user_id = %s
           order by cm.repetitions desc, c.term limit %s""",
        (user["id"], limite),
    )

    def niveau(reps: int, ease: float) -> str:
        if reps >= 4 and ease >= 2.4:
            return "acquis"
        if reps >= 2:
            return "en_cours"
        return "fragile"

    return [
        {
            "concept_id": str(l["id"]),
            "terme": l["term"],
            "axe": l["axe"],
            "axe_label": l["axe_label"],
            "revisions": l["repetitions"],
            "facilite": round(float(l["ease"]), 2),
            "niveau": niveau(l["repetitions"], float(l["ease"])),
            "prochaine_revision": l["next_review_at"],
        }
        for l in lignes
    ]


@router.get("/journal", summary="Le journal brut")
async def journal(user: CurrentUser, limite: Annotated[int, Query(le=200)] = 50):
    lignes = await fetch_all(
        """select pe.id, pe.type, pe.payload, pe.at, pe.document_id,
                  coalesce(d.title_clean, d.title_raw) as ouvrage
           from progress_event pe
           left join document d on d.id = pe.document_id
           where pe.user_id = %s order by pe.at desc limit %s""",
        (user["id"], limite),
    )
    return [
        {
            "id": str(l["id"]),
            "type": l["type"],
            "ouvrage": l["ouvrage"],
            "document_id": str(l["document_id"]) if l["document_id"] else None,
            "details": l["payload"],
            "le": l["at"],
        }
        for l in lignes
    ]
