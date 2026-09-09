"""L'agent : conversations ancrées dans le corpus."""
import json
from typing import Annotated

from fastapi import APIRouter, Query, status
from pydantic import BaseModel, Field

from app.core.db import connection, execute, fetch_all, fetch_one
from app.core.deps import CurrentUser
from app.core.errors import NotFound
from app.services import quotas, rag

router = APIRouter(prefix="/agent", tags=["Agent"])


class QuestionIn(BaseModel):
    question: str = Field(min_length=3, max_length=2000)
    conversation_id: str | None = None
    document_id: str | None = Field(default=None, description="restreindre à un ouvrage")
    axe: str | None = Field(default=None, description="restreindre à un axe")


@router.post("/questions", status_code=status.HTTP_201_CREATED, summary="Poser une question")
async def poser(data: QuestionIn, user: CurrentUser):
    compteur = await quotas.check(user, "agent_question")

    conversation_id = data.conversation_id
    if conversation_id:
        conv = await fetch_one(
            "select id from conversation where id = %s and user_id = %s",
            (conversation_id, user["id"]),
        )
        if not conv:
            raise NotFound("Cette conversation n'existe pas ou ne vous appartient pas.")
    else:
        conv = await fetch_one(
            """insert into conversation (user_id, document_id, title)
               values (%s, %s, %s) returning id""",
            (user["id"], data.document_id, data.question[:80]),
        )
        conversation_id = str(conv["id"])

    historique = await fetch_all(
        "select role, body from message where conversation_id = %s order by at desc limit 6",
        (conversation_id,),
    )
    historique.reverse()

    passages = await rag.passages_pertinents(
        data.question,
        document_id=data.document_id,
        axe=data.axe,
        limite=8,
    )
    resultat = await rag.repondre(data.question, passages, historique)
    citations = rag.citations_utilisees(resultat["reponse"], passages)

    async with connection() as conn:
        await conn.execute(
            "insert into message (conversation_id, role, body) values (%s, 'user', %s)",
            (conversation_id, data.question),
        )
        msg = await (await conn.execute(
            """insert into message (conversation_id, role, body, citations, model_id,
                                    cost_tokens_in, cost_tokens_out)
               values (%s, 'assistant', %s, %s::jsonb, %s, %s, %s) returning id, at""",
            (conversation_id, resultat["reponse"], json.dumps(citations),
             None if resultat["degrade"] else "claude", resultat["tokens_in"], resultat["tokens_out"]),
        )).fetchone()
        await conn.execute(
            "update conversation set last_at = now() where id = %s", (conversation_id,)
        )

    await quotas.record(user["id"], "agent_question")
    if resultat["tokens_in"] or resultat["tokens_out"]:
        await quotas.record(
            user["id"], "agent_tokens",
            quantity=1, cost_tokens=resultat["tokens_in"] + resultat["tokens_out"],
        )
    await execute(
        """insert into progress_event (user_id, document_id, type, payload)
           values (%s, %s, 'question_asked', %s::jsonb)""",
        (user["id"], data.document_id, json.dumps({"conversation_id": conversation_id})),
    )

    restant = compteur.get("restant")
    return {
        "conversation_id": conversation_id,
        "message_id": str(msg["id"]),
        "reponse": resultat["reponse"],
        "citations": citations,
        "degrade": resultat["degrade"],
        "quota": {
            "restant": None if restant is None else max(0, restant - 1),
            "limite": compteur.get("limite"),
        },
        "le": msg["at"],
    }


@router.get("/conversations", summary="Vos conversations")
async def conversations(user: CurrentUser, limite: Annotated[int, Query(le=100)] = 30):
    lignes = await fetch_all(
        """select c.id, c.title, c.last_at, c.created_at,
                  coalesce(d.title_clean, d.title_raw) as ouvrage, c.document_id,
                  (select count(*) from message m where m.conversation_id = c.id) as nb_messages
           from conversation c
           left join document d on d.id = c.document_id
           where c.user_id = %s order by c.last_at desc limit %s""",
        (user["id"], limite),
    )
    return [
        {
            "id": str(l["id"]),
            "titre": l["title"],
            "ouvrage": l["ouvrage"],
            "document_id": str(l["document_id"]) if l["document_id"] else None,
            "nb_messages": l["nb_messages"],
            "derniere_activite": l["last_at"],
        }
        for l in lignes
    ]


@router.get("/conversations/{conversation_id}", summary="Une conversation")
async def conversation(conversation_id: str, user: CurrentUser):
    conv = await fetch_one(
        """select c.id, c.title, c.document_id, c.created_at,
                  coalesce(d.title_clean, d.title_raw) as ouvrage
           from conversation c left join document d on d.id = c.document_id
           where c.id = %s and c.user_id = %s""",
        (conversation_id, user["id"]),
    )
    if not conv:
        raise NotFound("Cette conversation n'existe pas ou ne vous appartient pas.")
    messages = await fetch_all(
        """select id, role, body, citations, at from message
           where conversation_id = %s order by at""",
        (conversation_id,),
    )
    return {
        "id": str(conv["id"]),
        "titre": conv["title"],
        "ouvrage": conv["ouvrage"],
        "document_id": str(conv["document_id"]) if conv["document_id"] else None,
        "messages": [
            {
                "id": str(m["id"]),
                "role": m["role"],
                "texte": m["body"],
                "citations": m["citations"] or [],
                "le": m["at"],
            }
            for m in messages
        ],
    }


@router.delete("/conversations/{conversation_id}", status_code=204, summary="Supprimer")
async def supprimer(conversation_id: str, user: CurrentUser):
    n = await execute(
        "delete from conversation where id = %s and user_id = %s", (conversation_id, user["id"])
    )
    if not n:
        raise NotFound("Cette conversation n'existe pas ou ne vous appartient pas.")


@router.get("/suggestions", summary="Questions proposées dans un contexte de lecture")
async def suggestions(
    user: CurrentUser,
    document_id: Annotated[str | None, Query()] = None,
    chapitre_id: Annotated[str | None, Query()] = None,
):
    """Des questions tirées du contenu réel plutôt qu'une liste générique.

    On s'appuie sur les thèmes des citations retenues et sur les idées-force de
    la fiche : ce sont les objets sur lesquels l'agent aura effectivement de quoi
    répondre.
    """
    propositions: list[str] = []
    if chapitre_id:
        lignes = await fetch_all(
            """select content from derivative
               where chapter_id = %s and kind = 'citation' and superseded_by is null""",
            (chapitre_id,),
        )
        for l in lignes:
            for c in (l["content"] or {}).get("citations", [])[:3]:
                if c.get("theme"):
                    propositions.append(f"Explique-moi : {c['theme'].lower()}")
    if document_id and len(propositions) < 4:
        d = await fetch_one(
            """select p.central_thesis, p.key_ideas, coalesce(d.title_clean, d.title_raw) as titre
               from document d left join document_pedagogy p on p.document_id = d.id
               where d.id = %s""",
            (document_id,),
        )
        if d:
            if d["central_thesis"]:
                propositions.append("Quelle est la thèse centrale de cet ouvrage, en trois phrases ?")
            for idee in (d["key_ideas"] or [])[:3]:
                texte = idee if isinstance(idee, str) else (idee.get("titre") or idee.get("idee") or "")
                if texte:
                    propositions.append(f"Développe : {texte[:90]}")
            propositions.append("Quels ouvrages du corpus défendent la thèse opposée ?")
    if not propositions:
        propositions = [
            "Quels ouvrages me conseilles-tu pour commencer cet axe ?",
            "Résume-moi les idées-force de ce que je viens de lire.",
            "Sur quoi les auteurs du corpus se contredisent-ils ?",
        ]
    return {"suggestions": propositions[:6]}
