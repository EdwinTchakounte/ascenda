"""Les travaux périodiques.

Trois choses doivent tourner sans qu'on y pense :

- la **réconciliation** repêche les paiements dont la notification s'est perdue ;
- la **fermeture** coupe l'accès des abonnements arrivés à terme ;
- la **relance** prévient ceux dont l'abonnement se termine bientôt.

Ils tournent dans le processus de l'API plutôt que dans un ordonnanceur séparé :
à cette échelle, un conteneur de moins vaut mieux qu'une brique de plus. Le jour
où plusieurs instances tourneront en parallèle, il faudra un verrou pour qu'une
seule exécute le travail. Le verrou consultatif de PostgreSQL suffit, et il est
déjà posé ci-dessous.
"""
import asyncio
import logging
from datetime import datetime, timezone

from app.core.db import connection
from app.services.paiement import service

log = logging.getLogger("ascenda.ordonnanceur")

# Identifiants arbitraires mais stables des verrous consultatifs.
VERROU_RECONCILIATION = 815_001
VERROU_ABONNEMENTS = 815_002

PERIODE_RECONCILIATION = 15 * 60      # un quart d'heure
PERIODE_ABONNEMENTS = 60 * 60         # une heure


async def _avec_verrou(cle: int, travail) -> dict | None:
    """N'exécute le travail que si aucune autre instance ne le fait déjà."""
    async with connection() as conn:
        cur = await conn.execute("select pg_try_advisory_lock(%s) as pris", (cle,))
        if not (await cur.fetchone())["pris"]:
            return None
        try:
            return await travail()
        finally:
            await conn.execute("select pg_advisory_unlock(%s)", (cle,))


async def boucle_reconciliation() -> None:
    while True:
        await asyncio.sleep(PERIODE_RECONCILIATION)
        try:
            bilan = await _avec_verrou(VERROU_RECONCILIATION, service.reconcilier)
            if bilan and bilan["examines"]:
                log.info("Réconciliation : %s", bilan)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            # Une panne ici ne doit jamais arrêter la boucle : le prochain tour
            # repassera sur les mêmes paiements.
            log.exception("Réconciliation en échec, reprise au prochain tour.")


async def boucle_abonnements() -> None:
    while True:
        try:
            bilan = await _avec_verrou(VERROU_ABONNEMENTS, service.fermer_echus)
            if bilan and bilan["expires"]:
                log.info("Abonnements arrivés à terme : %s", bilan)

            # Les rappels ne dépendent pas des fermetures. Ils étaient jusqu'ici
            # dans le `if` ci-dessus : un jour où rien n'expirait, personne
            # n'était prévenu de son échéance à venir.
            if bilan is not None:
                from app.services.courriel import evenements

                relance = await evenements.rappels_echeance()
                if relance["envoyes"]:
                    log.info("Rappels d'échéance : %s", relance)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            log.exception("Fermeture des abonnements en échec, reprise au prochain tour.")
        await asyncio.sleep(PERIODE_ABONNEMENTS)


def demarrer() -> list[asyncio.Task]:
    log.info("Ordonnanceur démarré (réconciliation toutes les %s min, "
             "abonnements toutes les %s min).",
             PERIODE_RECONCILIATION // 60, PERIODE_ABONNEMENTS // 60)
    return [
        asyncio.create_task(boucle_reconciliation(), name="reconciliation"),
        asyncio.create_task(boucle_abonnements(), name="abonnements"),
    ]


async def arreter(taches: list[asyncio.Task]) -> None:
    for t in taches:
        t.cancel()
    await asyncio.gather(*taches, return_exceptions=True)
