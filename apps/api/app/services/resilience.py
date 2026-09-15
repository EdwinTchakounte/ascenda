"""Tenir quand une dépendance externe tombe : disjoncteurs et reprises.

ASCENDA dépend de trois services qu'il ne contrôle pas : Tara pour encaisser,
Brevo pour écrire, Anthropic pour rédiger les réponses de l'agent. Quand l'un
ralentit ou tombe, deux dégâts sont à éviter :

- **l'effet d'accumulation** : chaque requête attend son délai maximal, les
  connexions s'épuisent, et c'est toute l'API qui ne répond plus ;
- **l'acharnement** : relancer sans fin un service déjà à genoux l'empêche de
  se relever, et nous fait bannir.

Le disjoncteur répond au premier : après `seuil` échecs d'affilée, il s'ouvre et
refuse aussitôt, sans appel réseau, pendant `pause` secondes. Il laisse ensuite
passer un seul appel d'essai (demi-ouvert) : réussi, il se referme ; raté, il
repart pour une pause. L'état vit dans le processus : chaque instance de l'API
juge pour elle-même, ce qui suffit à protéger ses propres connexions.

Les reprises espacées répondent au second, pour ce qui peut attendre (un
courriel) : 1 min, 5 min, 30 min, 2 h, 6 h, puis abandon signalé.
"""
import asyncio
import logging
import random
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

log = logging.getLogger("ascenda.resilience")

FERME, OUVERT, DEMI_OUVERT = "ferme", "ouvert", "demi_ouvert"


class CircuitOuvert(Exception):
    """Le disjoncteur refuse l'appel : le service est jugé indisponible."""

    def __init__(self, nom: str, reessayer_dans: float):
        super().__init__(f"{nom} indisponible, nouvel essai dans {round(reessayer_dans)} s")
        self.nom = nom
        self.reessayer_dans = reessayer_dans


@dataclass
class Disjoncteur:
    nom: str
    seuil: int = 5
    pause: float = 60.0
    horloge: callable = time.monotonic
    etat: str = FERME
    echecs: int = 0
    ouvert_depuis: float | None = None
    dernier_echec: str | None = None
    ouvertures: int = 0
    _essai_en_cours: bool = field(default=False, repr=False)

    def _etat_courant(self) -> str:
        if self.etat == OUVERT and self.horloge() - (self.ouvert_depuis or 0) >= self.pause:
            return DEMI_OUVERT
        return self.etat

    def avant_appel(self) -> None:
        etat = self._etat_courant()
        if etat == OUVERT:
            raise CircuitOuvert(self.nom, self.pause - (self.horloge() - (self.ouvert_depuis or 0)))
        if etat == DEMI_OUVERT:
            # Un seul appel d'essai à la fois : les autres attendent son verdict.
            if self._essai_en_cours:
                raise CircuitOuvert(self.nom, 1)
            self.etat, self._essai_en_cours = DEMI_OUVERT, True

    def succes(self) -> None:
        if self.etat != FERME:
            log.info("Disjoncteur %s refermé.", self.nom)
        self.etat, self.echecs, self.ouvert_depuis, self._essai_en_cours = FERME, 0, None, False

    def echec(self, raison: str) -> None:
        self.dernier_echec = raison[:300]
        self._essai_en_cours = False
        if self.etat == DEMI_OUVERT:
            self._ouvrir()
            return
        self.echecs += 1
        if self.echecs >= self.seuil:
            self._ouvrir()

    def _ouvrir(self) -> None:
        self.etat, self.ouvert_depuis = OUVERT, self.horloge()
        self.ouvertures += 1
        log.warning("Disjoncteur %s ouvert pour %s s : %s", self.nom, self.pause, self.dernier_echec)

    async def appeler(self, fonction, *args, compte_comme_echec=lambda exc: True, **kwargs):
        """Exécute `fonction` sous la protection du disjoncteur.

        `compte_comme_echec` distingue une panne du service (délai dépassé,
        erreur 5xx) d'un refus métier (numéro invalide) : un lecteur qui se
        trompe de numéro ne doit pas couper la caisse pour tout le monde.
        """
        self.avant_appel()
        try:
            resultat = await fonction(*args, **kwargs)
        except CircuitOuvert:
            raise
        except Exception as exc:
            if compte_comme_echec(exc):
                self.echec(f"{type(exc).__name__}: {exc}")
            else:
                self.succes()
            raise
        self.succes()
        return resultat

    def vue(self) -> dict:
        etat = self._etat_courant()
        return {
            "nom": self.nom,
            "etat": etat,
            "echecs_consecutifs": self.echecs,
            "ouvertures": self.ouvertures,
            "dernier_echec": self.dernier_echec,
            "reessai_dans_s": (
                max(0, round(self.pause - (self.horloge() - self.ouvert_depuis)))
                if etat == OUVERT and self.ouvert_depuis is not None else None
            ),
        }


DISJONCTEURS: dict[str, Disjoncteur] = {
    "tara": Disjoncteur("tara", seuil=3, pause=120.0),
    "brevo": Disjoncteur("brevo", seuil=5, pause=60.0),
    "anthropic": Disjoncteur("anthropic", seuil=3, pause=90.0),
}


def disjoncteur(nom: str) -> Disjoncteur:
    return DISJONCTEURS[nom]


# ---------------------------------------------------------------- reprises

PALIERS_COURRIEL = [timedelta(minutes=1), timedelta(minutes=5), timedelta(minutes=30),
                    timedelta(hours=2), timedelta(hours=6)]


def prochaine_tentative(tentatives: int, maintenant: datetime | None = None,
                        paliers: list[timedelta] = PALIERS_COURRIEL) -> datetime | None:
    """La date du prochain essai après `tentatives` échecs, ou None pour abandonner.

    Un aléa de plus ou moins 10 % évite que cent messages en échec à la même
    minute repartent tous à la même seconde.
    """
    if tentatives > len(paliers):
        return None
    base = paliers[tentatives - 1]
    alea = base.total_seconds() * random.uniform(-0.1, 0.1)
    return (maintenant or datetime.now(timezone.utc)) + base + timedelta(seconds=alea)


async def avec_reprises(fonction, *args, essais: int = 3, base: float = 0.5,
                        rejouable=lambda exc: True, **kwargs):
    """Rejoue un appel sans effet de bord (une lecture) avec des pauses croissantes.

    À réserver aux opérations idempotentes : interroger le statut d'un paiement
    oui, déclencher une demande de paiement non, puisqu'un délai dépassé ne dit
    pas si la demande est partie vers le téléphone du lecteur.
    """
    for essai in range(1, essais + 1):
        try:
            return await fonction(*args, **kwargs)
        except CircuitOuvert:
            raise
        except Exception as exc:
            if essai == essais or not rejouable(exc):
                raise
            attente = base * (2 ** (essai - 1)) * random.uniform(0.8, 1.2)
            log.info("Nouvel essai %s/%s dans %.1f s : %s", essai + 1, essais, attente, exc)
            await asyncio.sleep(attente)
