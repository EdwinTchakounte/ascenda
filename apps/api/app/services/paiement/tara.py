"""Tara mobile money : MTN et Orange au Cameroun."""
import json
import logging
from typing import Any

import httpx

from app.core.config import settings
from app.services.resilience import CircuitOuvert, avec_reprises, disjoncteur

from .base import ErreurFournisseur, EvenementWebhook, FournisseurPaiement, ResultatInitiation

log = logging.getLogger("ascenda.paiement.tara")

# Table de correspondance des statuts Tara. Au niveau du module pour qu'on
# puisse l'étendre sans toucher à la classe.
STATUTS = {
    "SUCCESS": "valide",
    "VALIDATED": "valide",
    "COMPLETED": "valide",
    "PAID": "valide",
    "PENDING": "en_attente",
    "INITIATED": "en_attente",
    "FAILED": "rejete",
    "REJECTED": "rejete",
    "CANCELLED": "rejete",
    "ERROR": "rejete",
}


def normaliser_telephone(brut: str) -> str:
    """Tara attend les numéros camerounais en 2376XXXXXXXX, sans espace ni plus."""
    chiffres = "".join(c for c in (brut or "") if c.isdigit())
    if not chiffres:
        raise ErreurFournisseur("Numéro de téléphone vide.", rejouable=False)
    if chiffres.startswith("237"):
        return chiffres
    return f"237{chiffres.lstrip('0')}"


class Tara(FournisseurPaiement):
    code = "tara"
    BASE = "https://www.dklo.co"
    DELAI = 15.0

    def __init__(self) -> None:
        self.cle = settings.tara_api_key
        self.business_id = settings.tara_business_id

    @property
    def simule(self) -> bool:
        """Sans identifiants, on ne fait aucun appel sortant et on renvoie une référence factice."""
        return not (self.cle and self.business_id)

    # ------------------------------------------------------------------ payin

    async def initier(self, paiement: dict, *, telephone: str, reseau: str | None = None) -> ResultatInitiation:
        tel = normaliser_telephone(telephone)
        if self.simule:
            log.warning("Tara en mode simulé : aucun appel sortant.")
            return ResultatInitiation(
                reference_fournisseur=str(paiement["idempotency_key"]),
                brut={"simule": True, "raison": "TARA_API_KEY absente", "telephone": tel},
            )

        libelle = paiement.get("libelle") or "Abonnement ASCENDA"
        charge = {
            "apiKey": self.cle,
            "businessId": self.business_id,
            # C'est notre clé de rattachement nº 1. Tara la renvoie en principe
            # dans le webhook sous `productId`.
            "productId": str(paiement["idempotency_key"]),
            "productName": libelle,
            "productPrice": int(paiement["montant"]),  # entier XAF, pas une chaîne
            "phoneNumber": tel,
            "webHookUrl": self._url_webhook(),
            # Laissé vide volontairement : Tara déduit l'opérateur du préfixe.
            "network": "",
            "productDescription": f"{libelle}, ASCENDA",
            "returnUrl": self._url_retour(),
        }
        donnees = await self._poster("/api/tara/mobilepay", charge)
        log.info(
            "Tara initier : tel=%s montant=%s productId=%s reponse=%s",
            tel, charge["productPrice"], charge["productId"], donnees,
        )
        return ResultatInitiation(
            # Avant le webhook, Tara ne nous donne pas d'identifiant : on garde
            # le nôtre. Le `paymentId` arrivera avec la notification.
            reference_fournisseur=str(paiement["idempotency_key"]),
            url_paiement=donnees.get("authUrl"),  # Wave seulement, sinon absent
            brut={**donnees, "_telephone": tel, "_reseau": reseau},
        )

    # ----------------------------------------------------------------- statut

    async def statut(self, paiement: dict) -> str:
        if self.simule:
            # Le mode simulé ne valide jamais tout seul : la confirmation passe
            # par la route de développement prévue à cet effet.
            return "en_attente"
        # Une lecture : on peut la rejouer sans risque, avec des pauses croissantes.
        donnees = await avec_reprises(
            self._poster,
            "/api/tara/transactions/status",
            {
                "apiKey": self.cle,
                "businessId": self.business_id,
                "productId": str(paiement["idempotency_key"]),
            },
            essais=3, base=1.0, rejouable=lambda exc: getattr(exc, "rejouable", False),
        )
        return STATUTS.get((donnees.get("status") or "").upper(), "en_attente")

    # ---------------------------------------------------------------- webhook

    def lire_webhook(self, corps: bytes) -> EvenementWebhook:
        """Tara ne signe pas ses webhooks : ni HMAC, ni en-tête de signature. La sécurité tient au
        HTTPS et au fait que l'URL n'est connue que d'eux. On ajoute une vérification du
        `businessId` : deviner l'URL ne suffit alors plus, il faut aussi connaître notre.
        """
        try:
            charge: dict[str, Any] = json.loads(corps.decode("utf-8") or "{}")
        except (ValueError, UnicodeDecodeError) as exc:
            raise ErreurFournisseur(f"Webhook illisible : {exc}", rejouable=False) from exc

        recu = charge.get("businessId")
        if self.business_id and recu and str(recu) != str(self.business_id):
            raise ErreurFournisseur(
                f"Webhook destiné à un autre marchand ({recu!r}).", rejouable=False
            )

        return EvenementWebhook(
            cle_idempotence=str(charge.get("productId") or charge.get("collectionId") or ""),
            statut=STATUTS.get((charge.get("status") or "").upper(), "en_attente"),
            reference_fournisseur=str(charge.get("paymentId") or ""),
            telephone=str(charge.get("phoneNumber") or "") or None,
            brut=charge,
        )

    # -------------------------------------------------------------- interne

    def _url_webhook(self) -> str:
        return f"{settings.public_base_url.rstrip('/')}/v1/paiements/webhook/tara"

    def _url_retour(self) -> str:
        return f"{settings.public_base_url.rstrip('/')}/paiement/retour"

    async def _poster(self, chemin: str, charge: dict) -> dict:
        """Appel à Tara sous disjoncteur."""
        try:
            return await disjoncteur("tara").appeler(
                self._poster_brut, chemin, charge,
                compte_comme_echec=lambda exc: getattr(exc, "rejouable", True))
        except CircuitOuvert as exc:
            raise ErreurFournisseur(
                "Le service de paiement est momentanément indisponible.", rejouable=True) from exc

    async def _poster_brut(self, chemin: str, charge: dict) -> dict:
        try:
            async with httpx.AsyncClient(timeout=self.DELAI) as client:
                r = await client.post(f"{self.BASE}{chemin}", json=charge)
        except httpx.TimeoutException as exc:
            raise ErreurFournisseur(f"Tara ne répond pas sur {chemin}.", rejouable=True) from exc
        except httpx.HTTPError as exc:
            raise ErreurFournisseur(
                f"Erreur réseau vers Tara sur {chemin} : {exc}", rejouable=True
            ) from exc

        if r.status_code >= 500:
            raise ErreurFournisseur(
                f"Tara en erreur serveur sur {chemin} ({r.status_code}).",
                rejouable=True,
                brut={"status": r.status_code, "corps": r.text[:500]},
            )
        try:
            donnees = r.json()
        except ValueError as exc:
            raise ErreurFournisseur(
                f"Tara a répondu autre chose que du JSON sur {chemin} : {r.text[:200]}",
                rejouable=False,
            ) from exc

        if r.status_code >= 400:
            raise ErreurFournisseur(
                f"Tara refuse la requête sur {chemin} : {donnees.get('message') or r.status_code}",
                rejouable=False,
                brut=donnees,
            )
        # Tara signale parfois une erreur métier avec un code HTTP 200.
        if (donnees.get("status") or "").upper() in {"ERROR", "FAILED"}:
            raise ErreurFournisseur(
                f"Tara refuse l'opération : {donnees.get('message') or 'raison non précisée'}",
                rejouable=False,
                brut=donnees,
            )
        return donnees
