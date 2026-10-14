"""Quiz : 2 342 lots déjà générés, servis sans jamais livrer la réponse au client."""
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import CurrentUser, OptionalUser
from app.core.errors import NotFound
from app.services import srs

router = APIRouter(prefix="/quiz", tags=["Quiz"])


class ReponsesIn(BaseModel):
    reponses: dict[int, int] = Field(description="index de question -> index de choix")
    duree_sec: int | None = None
    session_id: str | None = None


@router.get("/document/{document_id}", summary="Quiz disponibles pour un ouvrage")
async def quiz_disponibles(document_id: str, user: OptionalUser):
    lignes = await fetch_all(
        """select dv.id, dv.chapter_id, c.ord, c.title, c.page_start, c.page_end,
                  jsonb_array_length(dv.content->'questions') as nb,
                  dv.content->>'motif' as motif
           from derivative dv
           left join chapter c on c.id = dv.chapter_id
           where dv.document_id = %s and dv.kind = 'quiz' and dv.superseded_by is null
           order by c.ord nulls last""",
        (document_id,),
    )
    if not lignes:
        raise NotFound("Aucun quiz n'a encore été préparé pour cet ouvrage.")
    return {
        "document_id": document_id,
        "total_questions": sum(l["nb"] or 0 for l in lignes),
        "chapitres": [
            {
                "quiz_id": str(l["id"]),
                "chapitre_id": str(l["chapter_id"]) if l["chapter_id"] else None,
                "ordre": l["ord"],
                "titre": l["title"],
                "page_debut": l["page_start"],
                "page_fin": l["page_end"],
                "nb_questions": l["nb"] or 0,
                # Un chapitre d'appareil (sommaire, bibliographie) est enregistré vide,
                # avec son motif : le compteur reste sincère.
                "motif_vide": l["motif"],
            }
            for l in lignes
        ],
    }


@router.get("/{quiz_id}", summary="Passer un quiz")
async def passer(quiz_id: str, user: OptionalUser):
    q = await fetch_one(
        """select dv.id, dv.document_id, dv.chapter_id, dv.content,
                  c.title as chapitre, c.ord,
                  coalesce(d.title_clean, d.title_raw) as ouvrage
           from derivative dv
           join document d on d.id = dv.document_id
           left join chapter c on c.id = dv.chapter_id
           where dv.id = %s and dv.kind = 'quiz' and dv.superseded_by is null""",
        (quiz_id,),
    )
    if not q:
        raise NotFound("Ce quiz n'existe pas.")
    questions = (q["content"] or {}).get("questions", [])
    if not questions:
        raise NotFound(
            (q["content"] or {}).get("motif")
            or "Ce chapitre ne comporte pas de questions."
        )
    return {
        "quiz_id": str(q["id"]),
        "ouvrage": q["ouvrage"],
        "document_id": str(q["document_id"]),
        "chapitre_id": str(q["chapter_id"]) if q["chapter_id"] else None,
        "chapitre": q["chapitre"],
        "questions": [
            # `reponse` et `explication` restent au serveur jusqu'à la correction.
            {
                "index": i,
                "question": qu["q"],
                "choix": qu["choix"],
                "niveau": qu.get("niveau"),
                "page": qu.get("page"),
            }
            for i, qu in enumerate(questions)
        ],
    }


@router.post("/{quiz_id}/corriger", summary="Corriger un quiz")
async def corriger(quiz_id: str, data: ReponsesIn, user: CurrentUser):
    q = await fetch_one(
        """select dv.id, dv.document_id, dv.chapter_id, dv.content
           from derivative dv where dv.id = %s and dv.kind = 'quiz'""",
        (quiz_id,),
    )
    if not q:
        raise NotFound("Ce quiz n'existe pas.")
    questions = (q["content"] or {}).get("questions", [])

    # Les citations du même chapitre servent de pièce justificative : on cherche
    # celle dont la page est la plus proche de celle visée par la question.
    citations = []
    if q["chapter_id"]:
        lignes = await fetch_all(
            """select content from derivative
               where chapter_id = %s and kind = 'citation' and superseded_by is null""",
            (q["chapter_id"],),
        )
        for l in lignes:
            citations += (l["content"] or {}).get("citations", [])

    def justificatif(page: int | None) -> dict | None:
        if not citations:
            return None
        if page is None:
            c = citations[0]
        else:
            c = min(citations, key=lambda x: abs((x.get("page") or 0) - page))
        return {"texte": c.get("texte"), "page": c.get("page"), "portee": c.get("portee")}

    details, justes = [], 0
    for i, qu in enumerate(questions):
        donnee = data.reponses.get(i)
        bonne = qu.get("reponse")
        ok = donnee is not None and donnee == bonne
        justes += 1 if ok else 0
        details.append(
            {
                "index": i,
                "question": qu["q"],
                "votre_reponse": donnee,
                "bonne_reponse": bonne,
                "juste": ok,
                "explication": qu.get("explication"),
                "page": qu.get("page"),
                "niveau": qu.get("niveau"),
                "extrait": justificatif(qu.get("page")),
            }
        )

    total = len(questions)
    score = round(justes / total, 3) if total else 0.0
    await execute(
        """insert into progress_event (user_id, session_id, document_id, type, payload)
           values (%s, %s, %s, 'quiz_attempt', %s::jsonb)""",
        (
            user["id"],
            data.session_id,
            q["document_id"],
            __import__("json").dumps(
                {
                    "quiz_id": str(q["id"]),
                    "chapitre_id": str(q["chapter_id"]) if q["chapter_id"] else None,
                    "score": score,
                    "justes": justes,
                    "total": total,
                    "duree_sec": data.duree_sec,
                }
            ),
        ),
    )
    # Les notions ratées repartent en révision espacée.
    await srs.enregistrer_echecs(
        user["id"], q["document_id"],
        [d for d in details if not d["juste"]], q["chapter_id"]
    )

    return {
        "quiz_id": str(q["id"]),
        "score": score,
        "justes": justes,
        "total": total,
        "reussi": score >= 0.7,
        "details": details,
    }


@router.get("/document/{document_id}/historique", summary="Vos tentatives sur cet ouvrage")
async def historique(document_id: str, user: CurrentUser, limite: Annotated[int, Query(le=100)] = 20):
    lignes = await fetch_all(
        """select payload, at from progress_event
           where user_id = %s and document_id = %s and type = 'quiz_attempt'
           order by at desc limit %s""",
        (user["id"], document_id, limite),
    )
    return [
        {
            "quiz_id": l["payload"].get("quiz_id"),
            "chapitre_id": l["payload"].get("chapitre_id"),
            "score": l["payload"].get("score"),
            "justes": l["payload"].get("justes"),
            "total": l["payload"].get("total"),
            "le": l["at"],
        }
        for l in lignes
    ]
