"""Contrat d'un fournisseur de paiement.

Repris presque tel quel du module `mail+paiement`, qui l'avait éprouvé en
production. Le garder abstrait coûte peu et évite de recâbler tout le service
le jour où un second fournisseur s'ajoute.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any


class ErreurFournisseur(Exception):
    """`rejouable` distingue une panne passagère d'un refus définitif : la
    première mérite une nouvelle tentative, la seconde jamais."""

    def __init__(self, message: str, *, rejouable: bool = False, brut: dict | None = None):
        super().__init__(message)
        self.message = message
        self.rejouable = rejouable
        self.brut = brut or {}


@dataclass
class ResultatInitiation:
    reference_fournisseur: str
    url_paiement: str | None = None
    brut: dict[str, Any] = field(default_factory=dict)


@dataclass
class EvenementWebhook:
    """Ce que le fournisseur nous dit, une fois normalisé."""

    cle_idempotence: str
    statut: str  # "valide" | "en_attente" | "rejete"
    reference_fournisseur: str
    telephone: str | None = None
    brut: dict[str, Any] = field(default_factory=dict)


class FournisseurPaiement(ABC):
    code: str = ""

    @abstractmethod
    async def initier(self, paiement: dict, *, telephone: str, reseau: str) -> ResultatInitiation:
        """Doit être idempotent : la même clé ne doit jamais débiter deux fois."""

    @abstractmethod
    async def statut(self, paiement: dict) -> str:
        """Retourne « valide », « en_attente » ou « rejete »."""

    @abstractmethod
    def lire_webhook(self, corps: bytes) -> EvenementWebhook:
        """Valide et normalise un webhook entrant."""
