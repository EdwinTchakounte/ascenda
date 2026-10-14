"""Recherche hybride : les mots et le sens."""
import asyncio
import logging
from functools import lru_cache

from app.core.config import settings
from app.core.db import connection, fetch_all, fetch_one

log = logging.getLogger("ascenda.recherche")

# e5 attend un préfixe explicite. « query: » pour ce qu'on cherche,
# « passage: » pour ce qu'on a indexé. L'omettre dégrade nettement la qualité.
PREFIXE_REQUETE = "query: "

# Constante d'amortissement de la fusion par rang réciproque. 60 est la valeur
# de la publication d'origine ; elle empêche la première place d'écraser tout.
K_FUSION = 60

_modele = None
_modele_tente = False


def _charger_modele():
    """Charge le modèle à la première question, jamais au démarrage."""
    global _modele, _modele_tente
    if _modele is not None or _modele_tente:
        return _modele
    _modele_tente = True
    try:
        from sentence_transformers import SentenceTransformer

        _modele = SentenceTransformer(settings.embed_model)
        log.info("Modèle de recherche chargé : %s", settings.embed_model)
    except Exception as exc:  # noqa: BLE001
        log.warning("Recherche sémantique indisponible (%s). Plein texte seul.", exc)
        _modele = None
    return _modele


@lru_cache(maxsize=1)
def _cache_disponibilite() -> dict:
    return {"verifie": False, "disponible": False}


SEUIL_VECTORISATION = 0.95


async def vecteurs_disponibles() -> bool:
    """Vrai si le corpus est vectorisé pour l'essentiel. Vérifié une fois."""
    etat = _cache_disponibilite()
    if not etat["verifie"]:
        r = await fetch_one(
            """select count(*) as total,
                      count(*) filter (where embedding is not null) as faits
                 from chunk"""
        )
        total = (r or {}).get("total") or 0
        faits = (r or {}).get("faits") or 0
        part = faits / total if total else 0.0
        etat["disponible"] = part >= SEUIL_VECTORISATION
        etat["verifie"] = True
        if 0 < part < SEUIL_VECTORISATION:
            log.info(
                "Vectorisation à %.0f %% (%d/%d) : recherche en plein texte "
                "jusqu'à %.0f %%.",
                part * 100, faits, total, SEUIL_VECTORISATION * 100,
            )
    return etat["disponible"]


async def prechauffer() -> None:
    """Charge le modèle en fond, dès le démarrage, si le corpus est vectorisé."""
    try:
        if not await vecteurs_disponibles():
            return
        await asyncio.to_thread(_charger_modele)
        if _modele is not None:
            log.info("Modèle de recherche préchargé : la première question ne l'attendra pas.")
    except Exception:  # noqa: BLE001
        log.exception("Préchauffage du modèle de recherche impossible.")


def oublier_disponibilite() -> None:
    """À appeler après une vectorisation pour que l'API en tienne compte."""
    _cache_disponibilite.cache_clear()


# Le seuil du planificateur, repris ici : en deçà, un chapitre est de
# l'appareil éditorial.
TOKENS_MIN_CHAPITRE = 300

_SANS_APPAREIL = """
    and not k.est_liminaire
    and not exists (
      select 1 from chapter c
       where c.id = k.chapter_id
         and (coalesce(c.token_count, 0) < %s
              or exists (select 1 from derivative dv
                          where dv.chapter_id = c.id and dv.kind = 'quiz'
                            and dv.superseded_by is null
                            and jsonb_array_length(dv.content->'questions') = 0)))
"""


def _filtres(document_id: str | None, axe: str | None) -> tuple[str, list]:
    conditions, params = ["d.takedown_status = 'none'"], []
    if document_id:
        conditions.append("k.document_id = %s")
        params.append(document_id)
    if axe:
        conditions.append(
            "exists (select 1 from document_axis da join axis a on a.id = da.axis_id "
            "where da.document_id = k.document_id and a.slug = %s)"
        )
        params.append(axe)
    return " and ".join(conditions) + _SANS_APPAREIL, params + [TOKENS_MIN_CHAPITRE]


async def _plein_texte(requete: str, where: str, params: list, limite: int) -> list[dict]:
    return await fetch_all(
        f"""select k.id, ts_rank_cd(k.tsv, websearch_to_tsquery('french', %s)) as score
            from chunk k join document d on d.id = k.document_id
            where {where} and k.tsv @@ websearch_to_tsquery('french', %s)
            order by score desc limit %s""",
        [requete] + params + [requete, limite],
    )


async def _semantique(requete: str, where: str, params: list, limite: int) -> list[dict]:
    modele = await asyncio.to_thread(_charger_modele)
    if modele is None:
        return []
    vecteur = await asyncio.to_thread(
        lambda: modele.encode(
            PREFIXE_REQUETE + requete, normalize_embeddings=True, show_progress_bar=False
        )
    )
    litteral = "[" + ",".join(f"{x:.6f}" for x in vecteur) + "]"
    # `<=>` est la distance cosinus de pgvector : plus petite, plus proche.
    #
    # Deux réglages posés pour cette seule requête. `random_page_cost` parce
    # que le planificateur, avec sa valeur par défaut faite pour des disques
    # mécaniques, juge l'index HNSW plus coûteux qu'un parcours complet et
    # préfère lire les douze mille vecteurs : mesuré, l'index répond en 1,5 ms
    # contre 60 ms. `hnsw.ef_search` parce que l'index est approché et que la
    # recherche est filtrée par ouvrage ou par axe : élargir la liste de
    # candidats évite de rendre moins de passages que demandé.
    async with connection() as conn:
        await conn.execute("set local random_page_cost = 1.1")
        await conn.execute("set local hnsw.ef_search = 100")
        cur = await conn.execute(
            f"""select k.id, 1 - (k.embedding <=> %s::vector) as score
                from chunk k join document d on d.id = k.document_id
                where {where} and k.embedding is not null
                order by k.embedding <=> %s::vector limit %s""",
            [litteral] + params + [litteral, limite],
        )
        return await cur.fetchall()


def _fusionner(listes: list[list[dict]], limite: int) -> list[str]:
    """Fusion par rang réciproque."""
    points: dict[str, float] = {}
    for liste in listes:
        for rang, ligne in enumerate(liste, start=1):
            cle = str(ligne["id"])
            points[cle] = points.get(cle, 0.0) + 1.0 / (K_FUSION + rang)
    return [cle for cle, _ in sorted(points.items(), key=lambda x: -x[1])[:limite]]


async def chercher(
    requete: str,
    *,
    document_id: str | None = None,
    axe: str | None = None,
    limite: int = 20,
) -> tuple[list[dict], str]:
    """Retourne (passages ordonnés, mode employé)."""
    where, params = _filtres(document_id, axe)
    profondeur = max(limite * 3, 40)

    plein = await _plein_texte(requete, where, params, profondeur)
    semantique: list[dict] = []
    mode = "plein_texte"

    if await vecteurs_disponibles():
        semantique = await _semantique(requete, where, params, profondeur)
        if semantique:
            mode = "hybride" if plein else "semantique"

    ordre = _fusionner([l for l in (plein, semantique) if l], limite)
    if not ordre:
        return [], mode

    # Une seule requête pour hydrater, en conservant l'ordre de la fusion.
    lignes = await fetch_all(
        """select k.id, k.document_id, k.chapter_id, k.page_start, k.page_end, k.text,
                  c.title as chapitre, c.ord as chapitre_ord,
                  coalesce(d.title_clean, d.title_raw) as ouvrage, d.authors,
                  d.redistributable, d.max_excerpt_chars
           from chunk k
           join document d on d.id = k.document_id
           left join chapter c on c.id = k.chapter_id
           where k.id = any(%s)""",
        (ordre,),
    )
    par_id = {str(l["id"]): l for l in lignes}
    return [par_id[i] for i in ordre if i in par_id], mode
