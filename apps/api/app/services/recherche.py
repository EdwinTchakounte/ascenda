"""Recherche hybride : les mots et le sens.

Deux voies complémentaires, et non concurrentes.

- Le **plein texte** (`tsvector` français) trouve les occurrences exactes. C'est
  imbattable sur un nom propre, une date, un terme technique.
- Le **vecteur** trouve ce qui parle de la même chose sans employer les mêmes
  mots. C'est la seule voie qui répond à « sur quoi les auteurs se
  contredisent-ils », qui ne partage aucun terme avec les passages utiles.

Les deux classements sont fusionnés par rang réciproque : un passage bien placé
dans l'une des deux listes remonte, sans qu'il faille calibrer des poids entre
deux scores qui n'ont pas la même échelle.

Tant que les vecteurs ne sont pas calculés, la recherche reste en plein texte et
le champ `mode` de la réponse le dit. Rien à changer côté client le jour où les
vecteurs arrivent.
"""
import asyncio
import logging
from functools import lru_cache

from app.core.config import settings
from app.core.db import fetch_all, fetch_one

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
    """Charge le modèle à la première question, jamais au démarrage.

    L'API doit pouvoir démarrer sur une machine sans le modèle : la recherche
    plein texte suffit à faire tourner le produit.
    """
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


# Part du corpus qu'il faut avoir vectorisée pour que la voie sémantique serve.
# En dessous, elle ne voit qu'une fraction des passages et remonte du bruit tout
# en se présentant comme « hybride » : mieux vaut le plein texte, qui couvre
# l'ensemble et ne ment pas sur ce qu'il fait.
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
    """Charge le modèle en fond, dès le démarrage, si le corpus est vectorisé.

    Le chargement prend une quarantaine de secondes. Laissé au premier appel,
    c'est le premier lecteur qui les paie, et il conclut que la recherche ne
    marche pas. La tâche est lancée après le démarrage et dans un fil séparé :
    l'API répond normalement pendant ce temps, et une machine sans le modèle se
    contente d'un avertissement au journal.
    """
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

# L'appareil est déjà identifié en base par un lot de quiz vide, posé un par un
# pendant la campagne de génération : 178 chapitres. On relit ce marquage plutôt
# que de redécouvrir la même chose par heuristique, comme le fait déjà le
# planificateur.
#
# Sans ce filtre, la recherche sémantique remontait des sommaires en tête de
# résultats. Le vecteur ne sait pas qu'un sommaire ne se lit pas.
#
# `est_liminaire` complète le marquage au niveau du passage : une page de
# copyright vit souvent dans un chapitre par ailleurs lisible, que le
# marquage par chapitre laisse donc passer. La colonne est posée une fois
# par la migration 009, plutôt que par une condition textuelle qui ruinerait
# l'index HNSW à chaque requête.
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
    # Le chargement pèse deux gigaoctets et l'encodage occupe le processeur
    # pendant des centaines de millisecondes. Sur la boucle d'évènements, la
    # première recherche gelait toute l'API : soixante secondes pendant
    # lesquelles aucune autre requête n'était servie. Les deux partent donc dans
    # un fil d'exécution séparé.
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
    return await fetch_all(
        f"""select k.id, 1 - (k.embedding <=> %s::vector) as score
            from chunk k join document d on d.id = k.document_id
            where {where} and k.embedding is not null
            order by k.embedding <=> %s::vector limit %s""",
        [litteral] + params + [litteral, limite],
    )


def _fusionner(listes: list[list[dict]], limite: int) -> list[str]:
    """Fusion par rang réciproque.

    On additionne 1 / (k + rang) sur chaque liste. Un passage présent dans les
    deux remonte devant un passage excellent dans une seule, ce qui est
    exactement ce qu'on veut : la convergence des deux méthodes est le meilleur
    signal disponible.
    """
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
