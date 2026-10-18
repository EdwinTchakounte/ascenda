"""Répétition espacée (SM-2 simplifié)."""
from datetime import datetime, timedelta, timezone

from app.core.db import execute, fetch_all, fetch_one

EASE_MIN, EASE_MAX = 1.3, 2.8


async def _concepts_de(texte: str, document_id: str | None) -> list[str]:
    """Repère les notions en jeu dans une question ratée."""
    if not texte or len(texte) < 10:
        return []

    lignes = await fetch_all(
        """select c.id,
                  exists (
                    select 1 from concept_occurrence co
                    join chunk k on k.id = co.chunk_id
                    where co.concept_id = c.id and k.document_id = %s::uuid
                  ) as dans_l_ouvrage,
                  length(c.term) as precision
             from concept c
            where length(c.term) >= 5
              and unaccent(%s) ilike '%%' || unaccent(c.term) || '%%'
            -- Le terme le plus long l'emporte : « apprentissage supervisé »
            -- est plus instructif que « apprentissage ».
            order by dans_l_ouvrage desc, precision desc
            limit 4""",
        (document_id, texte),
    )
    return [str(l["id"]) for l in lignes]


async def _concepts_du_chapitre(chapter_id: str | None, limite: int = 2) -> list[str]:
    """Repli : les notions les plus présentes dans le chapitre raté."""
    if not chapter_id:
        return []
    lignes = await fetch_all(
        """select co.concept_id, count(*) as n
             from concept_occurrence co
             join chunk k on k.id = co.chunk_id
            where k.chapter_id = %s::uuid
            group by co.concept_id
            order by count(*) filter (where co.is_definition) desc, n desc
            limit %s""",
        (chapter_id, limite),
    )
    return [str(l["concept_id"]) for l in lignes]


async def programmer(user_id: str, concept_id: str, reussi: bool) -> dict:
    etat = await fetch_one(
        """select ease, interval_days, repetitions from concept_mastery
           where user_id = %s and concept_id = %s""",
        (user_id, concept_id),
    )
    ease = float(etat["ease"]) if etat else 2.5
    interval = int(etat["interval_days"]) if etat else 1
    reps = int(etat["repetitions"]) if etat else 0

    maintenant = datetime.now(timezone.utc)
    if reussi:
        reps += 1
        ease = min(EASE_MAX, ease + 0.1)
        interval = 1 if reps == 1 else (3 if reps == 2 else max(1, round(interval * ease)))
        prochaine = maintenant + timedelta(days=interval)
    else:
        reps = 0
        ease = max(EASE_MIN, ease - 0.25)
        interval = 1
        prochaine = maintenant
    await execute(
        """insert into concept_mastery (user_id, concept_id, ease, interval_days,
                                        repetitions, next_review_at)
           values (%s, %s, %s, %s, %s, %s)
           on conflict (user_id, concept_id) do update
             set ease = excluded.ease, interval_days = excluded.interval_days,
                 repetitions = excluded.repetitions, next_review_at = excluded.next_review_at""",
        (user_id, concept_id, ease, interval, reps, prochaine),
    )
    return {"ease": ease, "interval_days": interval, "repetitions": reps, "next_review_at": prochaine}


async def enregistrer_echecs(
    user_id: str,
    document_id: str | None,
    echecs: list[dict],
    chapter_id: str | None = None,
) -> int:
    """Programme la révision de ce qui a été raté."""
    vus: set[str] = set()
    for e in echecs:
        texte = " ".join(
            x for x in (e.get("question"), e.get("explication")) if x
        )
        for cid in await _concepts_de(texte, document_id):
            vus.add(cid)

    if not vus and echecs:
        # Aucun terme reconnu : on ramène les notions du chapitre
        vus.update(await _concepts_du_chapitre(chapter_id))

    for cid in vus:
        await programmer(user_id, cid, reussi=False)
    return len(vus)


async def a_reviser(user_id: str, limite: int = 20) -> list[dict]:
    lignes = await fetch_all(
        """select c.id, c.term, c.definition, cm.ease, cm.interval_days,
                  cm.repetitions, cm.next_review_at, a.slug as axe, a.label as axe_label
           from concept_mastery cm
           join concept c on c.id = cm.concept_id
           left join axis a on a.id = c.axis_id
           where cm.user_id = %s and (cm.next_review_at is null or cm.next_review_at <= now())
           order by cm.next_review_at nulls first limit %s""",
        (user_id, limite),
    )
    return [
        {
            "concept_id": str(l["id"]),
            "terme": l["term"],
            "definition": l["definition"],
            "axe": l["axe"],
            "axe_label": l["axe_label"],
            "facilite": round(float(l["ease"]), 2),
            "intervalle_jours": l["interval_days"],
            "revisions": l["repetitions"],
            "a_revoir_depuis": l["next_review_at"],
        }
        for l in lignes
    ]
