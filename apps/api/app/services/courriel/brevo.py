"""Brevo, pour le courrier transactionnel.

Un seul point d'accès nous suffit : `POST /v3/smtp/email`. Nous n'utilisons pas
les gabarits hébergés chez Brevo, parce qu'un gabarit qui vit ailleurs que dans
notre base est un gabarit qu'on ne peut ni relire ni corriger depuis ici.
"""
import logging
import re

import httpx

from app.core.config import settings

from .base import ErreurCourriel, FournisseurCourriel, ResultatEnvoi

log = logging.getLogger("ascenda.courriel.brevo")

# « ASCENDA <ne-pas-repondre@ascenda.app> » se découpe en nom et adresse.
_EXPEDITEUR = re.compile(r"^\s*(?:(?P<nom>.*?)\s*<)?(?P<adresse>[^<>\s]+@[^<>\s]+?)>?\s*$")


def decouper_expediteur(brut: str) -> tuple[str, str]:
    m = _EXPEDITEUR.match(brut or "")
    if not m:
        raise ErreurCourriel(f"Expéditeur illisible : {brut!r}", rejouable=False)
    return (m.group("nom") or "ASCENDA"), m.group("adresse")


class Brevo(FournisseurCourriel):
    code = "brevo"
    BASE = "https://api.brevo.com"
    DELAI = 15.0

    def __init__(self) -> None:
        self.cle = settings.brevo_api_key

    @property
    def simule(self) -> bool:
        return not self.cle

    async def envoyer(
        self,
        *,
        destinataire: str,
        objet: str,
        html: str,
        texte: str,
        expediteur: str,
    ) -> ResultatEnvoi:
        if self.simule:
            log.warning("Brevo en mode simulé : « %s » vers %s n'est pas parti.", objet, destinataire)
            return ResultatEnvoi(brut={"simule": True, "raison": "BREVO_API_KEY absente"})

        nom, adresse = decouper_expediteur(expediteur)
        charge = {
            "sender": {"name": nom, "email": adresse},
            "to": [{"email": destinataire}],
            "subject": objet,
            "htmlContent": html,
            "textContent": texte,
        }
        try:
            async with httpx.AsyncClient(timeout=self.DELAI) as client:
                r = await client.post(
                    f"{self.BASE}/v3/smtp/email",
                    json=charge,
                    headers={"api-key": self.cle, "accept": "application/json"},
                )
        except httpx.TimeoutException as exc:
            raise ErreurCourriel("Brevo ne répond pas.", rejouable=True) from exc
        except httpx.HTTPError as exc:
            raise ErreurCourriel(f"Erreur réseau vers Brevo : {exc}", rejouable=True) from exc

        if r.status_code >= 500:
            raise ErreurCourriel(
                f"Brevo en erreur serveur ({r.status_code}).",
                rejouable=True,
                brut={"status": r.status_code, "corps": r.text[:500]},
            )
        # 429 : quota de la minute atteint. Rejouable, contrairement aux autres 4xx.
        if r.status_code == 429:
            raise ErreurCourriel("Brevo limite le débit.", rejouable=True)
        if r.status_code >= 400:
            try:
                donnees = r.json()
            except ValueError:
                donnees = {"corps": r.text[:200]}
            raise ErreurCourriel(
                f"Brevo refuse l'envoi : {donnees.get('message') or r.status_code}",
                rejouable=False,
                brut=donnees,
            )
        try:
            donnees = r.json()
        except ValueError:
            donnees = {}
        return ResultatEnvoi(reference=donnees.get("messageId"), brut=donnees)
