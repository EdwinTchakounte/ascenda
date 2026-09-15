"""Glossaire et révision espacée."""
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import BaseModel

from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import CurrentUser, OptionalUser
from app.core.errors import NotFound
from app.services import srs
from app.services.droits import tronquer
from app.services.passages import extrait as passage_extrait

router = APIRouter(prefix="/concepts", tags=["Concepts & révision"])


class RevisionIn(BaseModel):
    concept_id: str
    reussi: bool


@router.get("", summary="Glossaire")
async def glossaire(
    user: OptionalUser,
    axe: Annotated[str | None, Query()] = None,
    q: Annotated[str | None, Query(min_length=2)] = None,
    limite: Annotated[int, Query(ge=1, le=200)] = 50,
):
    where, params = ["true"], []
    if axe:
        where.append("a.slug = %s")
        params.append(axe)
    if q:
        where.append("unaccent(c.term) ilike unaccent(%s)")
        params.append(f"%{q}%")
    lignes = await fetch_all(
        f"""select c.id, c.term, c.definition, a.slug as axe, a.label as axe_label,
                   (select count(*) from concept_occurrence co where co.concept_id = c.id) as occurrences
            from concept c left join axis a on a.id = c.axis_id
            where {' and '.join(where)}
            order by c.term limit %s""",
        params + [limite],
    )
    return [
        {
            "id": str(l["id"]),
            "terme": l["term"],
            "definition": l["definition"],
            "axe": l["axe"],
            "axe_label": l["axe_label"],
            "occurrences": l["occurrences"],
        }
        for l in lignes
    ]


@router.get("/a-reviser", summary="Les notions à revoir aujourd'hui")
async def a_reviser(user: CurrentUser, limite: Annotated[int, Query(le=50)] = 20):
    items = await srs.a_reviser(user["id"], limite)
    return {"total": len(items), "notions": items}


@router.post("/revision", summary="Enregistrer une révision")
async def reviser(data: RevisionIn, user: CurrentUser):
    if not await fetch_one("select 1 from concept where id = %s", (data.concept_id,)):
        raise NotFound("Cette notion n'existe pas.")
    etat = await srs.programmer(user["id"], data.concept_id, data.reussi)
    if data.reussi and etat["repetitions"] >= 3:
        await execute(
            """insert into progress_event (user_id, type, payload)
               values (%s, 'concept_mastered', %s::jsonb)""",
            (user["id"], __import__("json").dumps({"concept_id": data.concept_id})),
        )
    return {"concept_id": data.concept_id, **etat}


@router.get("/{concept_id}", summary="Une notion et ses occurrences dans le corpus")
async def detail(concept_id: str, user: OptionalUser):
    c = await fetch_one(
        """select c.id, c.term, c.definition, a.slug as axe, a.label as axe_label
           from concept c left join axis a on a.id = c.axis_id where c.id = %s""",
        (concept_id,),
    )
    if not c:
        raise NotFound("Cette notion n'existe pas.")
    occurrences = await fetch_all(
        """select k.id, k.page_start, k.text, co.is_definition,
                  d.id as document_id, coalesce(d.title_clean, d.title_raw) as ouvrage,
                  d.redistributable, d.max_excerpt_chars,
                  ch.id as chapitre_id, ch.title as chapitre
           from concept_occurrence co
           join chunk k on k.id = co.chunk_id
           join document d on d.id = k.document_id
           left join chapter ch on ch.id = k.chapter_id
           where co.concept_id = %s and d.takedown_status = 'none'
           order by co.is_definition desc, d.title_clean limit 12""",
        (concept_id,),
    )
    return {
        "id": str(c["id"]),
        "terme": c["term"],
        "definition": c["definition"],
        "axe": c["axe"],
        "axe_label": c["axe_label"],
        "occurrences": [
            {
                "document_id": str(o["document_id"]),
                "ouvrage": o["ouvrage"],
                "chapitre_id": str(o["chapitre_id"]) if o["chapitre_id"] else None,
                "chapitre": o["chapitre"],
                "page": o["page_start"],
                "definition": o["is_definition"],
                "extrait": tronquer(
                    passage_extrait(o["text"]),
                    600 if o["redistributable"] else min(300, int(o["max_excerpt_chars"] or 0)),
                )[0],
            }
            for o in occurrences
        ],
    }
