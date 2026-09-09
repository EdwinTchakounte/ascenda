"""Le contrat d'un fournisseur d'envoi de courriel.

Même forme que pour le paiement : une interface étroite, un mode simulé quand
la configuration manque, et des erreurs qui disent si l'on peut rejouer. Un
courriel qui ne part pas ne doit jamais faire tomber ce qui l'a déclenché.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field


class ErreurCourriel(Exception):
    def __init__(self, message: str, *, rejouable: bool = False, brut: dict | None = None):
        super().__init__(message)
        self.message = message
        self.rejouable = rejouable
        self.brut = brut or {}


@dataclass
class ResultatEnvoi:
    """Ce que le fournisseur renvoie quand il a accepté le message."""

    reference: str | None = None
    brut: dict = field(default_factory=dict)


class FournisseurCourriel(ABC):
    code: str

    @property
    @abstractmethod
    def simule(self) -> bool:
        """Vrai quand la configuration manque : on journalise sans rien envoyer."""

    @abstractmethod
    async def envoyer(
        self,
        *,
        destinataire: str,
        objet: str,
        html: str,
        texte: str,
        expediteur: str,
    ) -> ResultatEnvoi: ...
