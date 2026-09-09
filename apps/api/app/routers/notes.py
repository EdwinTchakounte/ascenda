"""Notes et surlignages, toujours rattachés à une page."""
from typing import Annotated

from fastapi import APIRouter, Query, status
from pydantic import BaseModel, Field

from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import CurrentUser
from app.core.errors import NotFound

router = APIRouter(tags=["Notes"])


class NoteIn(BaseModel):
    document_id: str | None = None
    chunk_id: str | None = None
    page: int | None = None
    texte: str = Field(min_length=1, max_length=8000)


class SurlignageIn(BaseModel):
    document_id: str
    chunk_id: str | None = None
    page: int | None = None
    citation: str = Field(min_length=1, max_length=2000)
    couleur: str = Field(default="or", pattern="^(or|sauge|terracotta|ardoise)$")


@router.get("/notes", summary="Vos notes")
async def lister_notes(
    user: CurrentUser,
    document_id: Annotated[str | None, Query()] = None,
    limite: Annotated[int, Query(le=200)] = 50,
):
    where, params = ["n.user_id = %s"], [user["id"]]
    if document_id:
        where.append("n.document_id = %s")
        params.append(document_id)
    lignes = await fetch_all(
        f"""select n.id, n.document_id, n.chunk_id, n.page, n.body, n.created_at, n.updated_at,
                   coalesce(d.title_clean, d.title_raw) as ouvrage,
                   c.title as chapitre, c.id as chapitre_id
            from note n
            left join document d on d.id = n.document_id
            left join chunk k on k.id = n.chunk_id
            left join chapter c on c.id = k.chapter_id
            where {' and '.join(where)}
            order by n.created_at desc limit %s""",
        params + [limite],
    )
    return [
        {
            "id": str(l["id"]),
            "document_id": str(l["document_id"]) if l["document_id"] else None,
            "ouvrage": l["ouvrage"],
            "chapitre_id": str(l["chapitre_id"]) if l["chapitre_id"] else None,
            "chapitre": l["chapitre"],
            "page": l["page"],
            "texte": l["body"],
            "cree_le": l["created_at"],
            "modifie_le": l["updated_at"],
        }
        for l in lignes
    ]


@router.post("/notes", status_code=status.HTTP_201_CREATED, summary="Écrire une note")
async def creer_note(data: NoteIn, user: CurrentUser):
    n = await fetch_one(
        """insert into note (user_id, document_id, chunk_id, page, body)
           values (%s, %s, %s, %s, %s) returning id, created_at""",
        (user["id"], data.document_id, data.chunk_id, data.page, data.texte),
    )
    await execute(
        """insert into progress_event (user_id, document_id, type, payload)
           values (%s, %s, 'note_created', '{}'::jsonb)""",
        (user["id"], data.document_id),
    )
    return {"id": str(n["id"]), "cree_le": n["created_at"]}


@router.patch("/notes/{note_id}", summary="Modifier une note")
async def modifier_note(note_id: str, data: NoteIn, user: CurrentUser):
    n = await execute(
        "update note set body = %s, updated_at = now() where id = %s and user_id = %s",
        (data.texte, note_id, user["id"]),
    )
    if not n:
        raise NotFound("Cette note n'existe pas ou ne vous appartient pas.")
    return {"id": note_id}


@router.delete("/notes/{note_id}", status_code=204, summary="Supprimer une note")
async def supprimer_note(note_id: str, user: CurrentUser):
    if not await execute("delete from note where id = %s and user_id = %s", (note_id, user["id"])):
        raise NotFound("Cette note n'existe pas ou ne vous appartient pas.")


@router.get("/surlignages", summary="Vos surlignages")
async def lister_surlignages(
    user: CurrentUser, document_id: Annotated[str | None, Query()] = None
):
    where, params = ["h.user_id = %s"], [user["id"]]
    if document_id:
        where.append("h.document_id = %s")
        params.append(document_id)
    lignes = await fetch_all(
        f"""select h.id, h.document_id, h.chunk_id, h.page, h.quote, h.color, h.created_at,
                   coalesce(d.title_clean, d.title_raw) as ouvrage
            from highlight h join document d on d.id = h.document_id
            where {' and '.join(where)} order by h.page nulls last, h.created_at""",
        params,
    )
    return [
        {
            "id": str(l["id"]),
            "document_id": str(l["document_id"]),
            "ouvrage": l["ouvrage"],
            "chunk_id": str(l["chunk_id"]) if l["chunk_id"] else None,
            "page": l["page"],
            "citation": l["quote"],
            "couleur": l["color"],
            "cree_le": l["created_at"],
        }
        for l in lignes
    ]


@router.post("/surlignages", status_code=status.HTTP_201_CREATED, summary="Surligner")
async def creer_surlignage(data: SurlignageIn, user: CurrentUser):
    h = await fetch_one(
        """insert into highlight (user_id, document_id, chunk_id, page, quote, color)
           values (%s, %s, %s, %s, %s, %s) returning id, created_at""",
        (user["id"], data.document_id, data.chunk_id, data.page, data.citation, data.couleur),
    )
    return {"id": str(h["id"]), "cree_le": h["created_at"]}


@router.delete("/surlignages/{surlignage_id}", status_code=204, summary="Retirer un surlignage")
async def supprimer_surlignage(surlignage_id: str, user: CurrentUser):
    if not await execute(
        "delete from highlight where id = %s and user_id = %s", (surlignage_id, user["id"])
    ):
        raise NotFound("Ce surlignage n'existe pas ou ne vous appartient pas.")
