"""Recherche ancrée : tout résultat porte son ouvrage, son chapitre et sa page.

Les embeddings ne sont pas encore calculés sur le corpus (0 / 11 395 chunks).
La recherche s'appuie donc sur tsvector français, qui répond en millisecondes.
Le jour où les vecteurs existent, `mode=semantique` s'ajoute ici sans changer
le contrat de sortie : c'est pourquoi la réponse porte déjà un champ `mode`.
"""
from typing import Annotated

from fastapi import APIRouter, Query

from app.core.db import fetch_all
from app.services import recherche
from app.core.deps import OptionalUser
from app.services.droits import tronquer

router = APIRouter(prefix="/recherche", tags=["Recherche"])


@router.get("", summary="Rechercher dans le corpus")
async def rechercher(
    user: OptionalUser,
    q: Annotated[str, Query(min_length=2, description="mots recherchés")],
    axe: Annotated[str | None, Query()] = None,
    document_id: Annotated[str | None, Query()] = None,
    limite: Annotated[int, Query(ge=1, le=50)] = 20,
):
    lignes, mode = await recherche.chercher(
        q, document_id=document_id, axe=axe, limite=limite
    )
    resultats = []
    for l in lignes:
        # Un extrait de recherche est court par nature ; on applique quand même
        # le plafond de l'ouvrage, et jamais plus de 400 caractères ici.
        budget = 10_000 if l["redistributable"] else min(400, int(l["max_excerpt_chars"] or 0))
        extrait, _ = tronquer(l["text"], max(budget, 0))
        resultats.append(
            {
                "chunk_id": str(l["id"]),
                "document_id": str(l["document_id"]),
                "ouvrage": l["ouvrage"],
                "auteurs": l["authors"] or [],
                "chapitre_id": str(l["chapter_id"]) if l["chapter_id"] else None,
                "chapitre": l["chapitre"],
                "page": l["page_start"],
                "page_fin": l["page_end"],
                "extrait": extrait,
            }
        )
    return {"requete": q, "mode": mode, "total": len(resultats), "resultats": resultats}


@router.get("/suggestions", summary="Complétion sur les titres, auteurs et concepts")
async def suggestions(q: Annotated[str, Query(min_length=2)], limite: int = 8):
    ouvrages = await fetch_all(
        """select id, coalesce(title_clean, title_raw) as titre, authors
           from document
           where takedown_status = 'none'
             and unaccent(coalesce(title_clean, title_raw)) ilike unaccent(%s)
           order by similarity(coalesce(title_clean, title_raw), %s) desc limit %s""",
        (f"%{q}%", q, limite),
    )
    concepts = await fetch_all(
        """select id, term, definition from concept
           where unaccent(term) ilike unaccent(%s)
           order by similarity(term, %s) desc limit %s""",
        (f"%{q}%", q, limite),
    )
    return {
        "ouvrages": [
            {"id": str(o["id"]), "titre": o["titre"], "auteurs": o["authors"] or []} for o in ouvrages
        ],
        "concepts": [
            {"id": str(c["id"]), "terme": c["term"], "definition": c["definition"]} for c in concepts
        ],
    }
