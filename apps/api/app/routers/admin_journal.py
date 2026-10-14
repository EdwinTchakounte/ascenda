"""La console : lire le journal des modifications écrit par les triggers."""
from typing import Annotated, Any

from fastapi import APIRouter, Query

from app.core.db import fetch_all, fetch_one
from app.core.deps import AdminUser
from app.core.errors import NotFound

router = APIRouter(prefix="/admin", tags=["Administration"])

PAR_PAGE = 40
COUPE = 120


def _lisible(v: Any) -> str:
    """Une valeur de colonne, rendue courte et lisible dans un tableau."""
    if v is None:
        return "—"
    if isinstance(v, bool):
        return "oui" if v else "non"
    texte = v if isinstance(v, str) else str(v)
    return texte if len(texte) <= COUPE else texte[: COUPE - 1].rstrip() + "…"


def _changements(ecart: dict | None) -> list[dict]:
    if not ecart:
        return []
    return [
        {"champ": champ, "avant": _lisible(paire[0]), "apres": _lisible(paire[1])}
        for champ, paire in sorted(ecart.items())
        if isinstance(paire, list) and len(paire) == 2
    ]


def _resume(operation: str, ecart: dict | None) -> str:
    if operation == "insert":
        return "ligne créée"
    if operation == "delete":
        return "ligne supprimée"
    champs = [c["champ"] for c in _changements(ecart)]
    if not champs:
        return "sans changement"
    if len(champs) <= 3:
        return ", ".join(champs)
    return f"{', '.join(champs[:3])} et {len(champs) - 3} de plus"


@router.get("/journal", summary="Le journal des modifications")
async def journal(
    user: AdminUser,
    relation: Annotated[str | None, Query(max_length=64)] = None,
    acteur: Annotated[str | None, Query(max_length=120)] = None,
    operation: Annotated[str | None, Query(pattern="^(insert|update|delete)$")] = None,
    jours: Annotated[int, Query(ge=1, le=365)] = 30,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    where = ["au >= now() - make_interval(days => %s)"]
    params: list[Any] = [jours]
    if relation:
        where.append("relation = %s")
        params.append(relation)
    if operation:
        where.append("operation = %s")
        params.append(operation)
    if acteur:
        where.append("acteur ilike %s")
        params.append(f"%{acteur}%")
    filtre = " and ".join(where)

    compte = await fetch_one(
        f"select count(*) as n from journal_modification where {filtre}", params)
    lignes = await fetch_all(
        f"""select id, au, relation, operation, cle, acteur, ecart
              from journal_modification where {filtre}
             order by au desc, id desc limit %s offset %s""",
        params + [par_page, (page - 1) * par_page],
    )
    # Les tables surveillées, pour peupler le filtre sans le coder en dur.
    relations = await fetch_all(
        """select c.relname as relation
             from pg_trigger t join pg_class c on c.oid = t.tgrelid
            where not t.tgisinternal and t.tgname like 'tracer\\_%'
            order by 1""")
    total = compte["n"] if compte else 0
    return {
        "lignes": [
            {"id": l["id"], "le": l["au"], "table": l["relation"], "operation": l["operation"],
             "ligne": l["cle"], "acteur": l["acteur"], "resume": _resume(l["operation"], l["ecart"]),
             "changements": _changements(l["ecart"])}
            for l in lignes
        ],
        "total": total,
        "page": page,
        "par_page": par_page,
        "pages": max(1, -(-total // par_page)),
        "relations": [r["relation"] for r in relations],
    }


@router.get("/journal/{entree_id}", summary="Une modification, ligne entière")
async def entree(user: AdminUser, entree_id: int):
    """L'état complet avant et après, quand l'écart ne suffit pas à comprendre."""
    l = await fetch_one(
        """select id, au, relation, operation, cle, acteur, avant, apres, ecart
             from journal_modification where id = %s""", (entree_id,))
    if not l:
        raise NotFound("Cette entrée de journal n'existe pas.")
    return {
        "id": l["id"], "le": l["au"], "table": l["relation"], "operation": l["operation"],
        "ligne": l["cle"], "acteur": l["acteur"],
        "changements": _changements(l["ecart"]),
        "avant": l["avant"], "apres": l["apres"],
    }
