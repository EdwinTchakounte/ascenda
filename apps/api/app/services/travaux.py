"""La file des travaux longs.

Ingérer un ouvrage prend des minutes, l'OCR des heures. L'API ne fait
qu'inscrire ce qu'il y a à faire ; un ouvrier séparé le prend et l'exécute.

Deux raisons de séparer. Une requête HTTP qui dure dix minutes est une requête
qui échoue : le navigateur abandonne, le proxy coupe, et celui qui a déposé le
fichier ne sait pas si son travail a commencé. Et l'image de l'API ne porte pas
le pipeline, délibérément : elle sert la base, elle ne la fabrique pas.
"""
import json
import logging
from typing import Any

from app.core.db import execute, fetch_all, fetch_one

log = logging.getLogger("ascenda.travaux")

# Ce que chaque type de travail lance, et ce qu'on lui passe. L'ouvrier lit
# cette table : ajouter un type se fait ici et nulle part ailleurs.
RECETTES: dict[str, dict[str, Any]] = {
    "ingestion": {
        "libelle": "Ingérer un ouvrage",
        "commande": ["pipeline/ingest/ingest.py"],
        "minutes": 5,
    },
    "structure": {
        "libelle": "Reconstituer les chapitres",
        "commande": ["pipeline/ingest/structure.py", "--tous"],
        "minutes": 10,
    },
    "passages": {
        "libelle": "Reconstruire les passages",
        "commande": ["pipeline/ingest/reparer_passages.py", "--tous"],
        "minutes": 10,
    },
    "vecteurs": {
        "libelle": "Vectoriser le corpus",
        "commande": ["pipeline/embed/embed.py", "--lot", "128"],
        "minutes": 600,
    },
    "derive": {
        "libelle": "Produire les dérivés",
        "commande": ["pipeline/derive/derive.py", "--sync"],
        "minutes": 120,
    },
    "import_data": {
        "libelle": "Importer data/ vers la base",
        "commande": ["pipeline/derive/importer.py"],
        "minutes": 2,
    },
}


async def inscrire(type_: str, charge: dict | None = None,
                   document_id: str | None = None,
                   demande_par: str | None = None) -> dict:
    """Met un travail dans la file.

    Un même travail lourd déjà en attente n'est pas inscrit deux fois : deux
    vectorisations en parallèle se disputeraient le processeur et la base pour
    faire deux fois le même ouvrage.
    """
    if type_ not in RECETTES:
        raise ValueError(f"Type de travail inconnu : {type_}")

    if document_id is None:
        double = await fetch_one(
            """select id from travail
                where type = %s and etat in ('en_attente', 'en_cours') limit 1""",
            (type_,),
        )
        if double:
            return {**dict(double), "deja": True}

    ligne = await fetch_one(
        """insert into travail (type, charge, document_id, demande_par)
           values (%s, %s::jsonb, %s, %s) returning *""",
        (type_, json.dumps(charge or {}), document_id, demande_par),
    )
    log.info("Travail inscrit : %s %s", type_, ligne["id"])
    return dict(ligne)


async def lister(etat: str | None = None, limite: int = 40, saut: int = 0) -> tuple[list, int]:
    where, params = ["true"], []
    if etat:
        where.append("t.etat = %s")
        params.append(etat)
    total = await fetch_one(
        f"select count(*) as n from travail t where {' and '.join(where)}", params
    )
    lignes = await fetch_all(
        f"""select t.*, coalesce(d.title_clean, d.title_raw) as ouvrage, u.email as demandeur
              from travail t
              left join document d on d.id = t.document_id
              left join app_user u on u.id = t.demande_par
             where {' and '.join(where)}
             order by t.created_at desc limit %s offset %s""",
        params + [limite, saut],
    )
    return [_vue(l) for l in lignes], total["n"]


async def un(travail_id: str) -> dict | None:
    ligne = await fetch_one(
        """select t.*, coalesce(d.title_clean, d.title_raw) as ouvrage, u.email as demandeur
             from travail t
             left join document d on d.id = t.document_id
             left join app_user u on u.id = t.demande_par
            where t.id = %s""",
        (travail_id,),
    )
    return _vue(ligne) if ligne else None


async def annuler(travail_id: str) -> bool:
    """Annule un travail qui n'a pas encore commencé.

    Un travail en cours ne s'annule pas d'ici : il tourne dans un autre
    processus, et le tuer à mi-parcours laisserait la base à moitié écrite.
    """
    ligne = await fetch_one(
        """update travail set etat = 'annule', finished_at = now()
            where id = %s and etat = 'en_attente' returning id""",
        (travail_id,),
    )
    return ligne is not None


async def relancer(travail_id: str) -> dict | None:
    """Remet un travail échoué dans la file, sans perdre ce qu'il avait dit."""
    ligne = await fetch_one(
        """update travail
              set etat = 'en_attente', erreur = null, progression = 0,
                  started_at = null, finished_at = null
            where id = %s and etat in ('echec', 'annule') returning *""",
        (travail_id,),
    )
    return dict(ligne) if ligne else None


async def purger(jours: int = 30) -> int:
    """Efface les travaux terminés anciens. La file est un outil de suivi, pas
    une archive : garder six mois de lignes réussies n'apprend rien."""
    await execute(
        """delete from travail
            where etat in ('termine', 'annule')
              and finished_at < now() - make_interval(days => %s)""",
        (jours,),
    )
    return jours


def _vue(l: dict) -> dict:
    recette = RECETTES.get(l["type"], {})
    return {
        "id": str(l["id"]),
        "type": l["type"],
        "libelle": recette.get("libelle", l["type"]),
        "etat": l["etat"],
        "progression": l["progression"],
        "ouvrage": l.get("ouvrage"),
        "document_id": str(l["document_id"]) if l["document_id"] else None,
        "charge": l["charge"],
        "journal": (l["journal"] or "")[-4000:],
        "erreur": l["erreur"],
        "demandeur": l.get("demandeur"),
        "cree_le": l["created_at"],
        "commence_le": l["started_at"],
        "fini_le": l["finished_at"],
        "duree_attendue_min": recette.get("minutes"),
    }
