"""L'envoi de courriel, du gabarit en base jusqu'à la trace.

Trois garanties, dans cet ordre :

1. **Rien ne remonte.** `envoyer` n'échoue jamais vers son appelant. Un courriel
   part d'un webhook de paiement ou de l'ordonnanceur : si une panne Brevo
   faisait tomber la chaîne, un membre payé n'obtiendrait pas son abonnement
   parce que le reçu n'est pas parti. C'est l'inverse de ce qu'on veut.
2. **Tout est tracé.** Chaque tentative laisse une ligne dans `email_log`,
   y compris les échecs et les envois simulés. On sait après coup ce qui est
   parti, vers qui, et pourquoi le reste n'est pas parti.
3. **Le gabarit vit en base.** Corriger une faute dans un message n'exige pas de
   redéployer, et le drapeau `actif` sert d'interrupteur.
"""
import logging

from app.core.config import settings
from app.core.db import execute, fetch_one

from .base import ErreurCourriel
from .brevo import Brevo
from .gabarit import envelopper, rendre

log = logging.getLogger("ascenda.courriel")

_fournisseur: Brevo | None = None


def fournisseur() -> Brevo:
    global _fournisseur
    if _fournisseur is None:
        _fournisseur = Brevo()
    return _fournisseur


def _texte_de_secours(html: str) -> str:
    """Une version texte grossière, quand le gabarit n'en fournit pas.

    Les clients qui n'affichent pas le HTML sont rares, mais un message sans
    partie texte est plus souvent classé indésirable.
    """
    import re

    sans_balises = re.sub(r"<br\s*/?>|</p>|</li>", "\n", html)
    sans_balises = re.sub(r"<[^>]+>", "", sans_balises)
    lignes = [l.strip() for l in sans_balises.splitlines()]
    return "\n".join(l for l in lignes if l)


async def envoyer(
    code: str,
    *,
    destinataire: str,
    contexte: dict | None = None,
    user_id: str | None = None,
) -> str:
    """Envoie le message `code` et renvoie le statut journalisé.

    Renvoie l'un de `envoye`, `simule`, `echec`, `ignore`. Ne lève jamais.
    """
    contexte = {"marque": "ASCENDA", **(contexte or {})}

    try:
        gabarit = await fetch_one(
            "select code, objet, corps_html, corps_texte, actif from email_template where code = %s",
            (code,),
        )
    except Exception:  # noqa: BLE001
        log.exception("Lecture du gabarit %r impossible.", code)
        return "echec"

    if not gabarit:
        # Un gabarit absent est une erreur de configuration, pas un incident
        # d'exploitation : on le dit fort.
        log.error("Gabarit de courriel %r introuvable.", code)
        return "ignore"
    if not gabarit["actif"]:
        log.info("Gabarit %r désactivé : rien n'est envoyé.", code)
        return "ignore"

    objet = rendre(gabarit["objet"], contexte)
    corps = rendre(gabarit["corps_html"], contexte)
    html = envelopper(code, objet, corps)
    texte = rendre(gabarit["corps_texte"] or "", contexte) or _texte_de_secours(corps)

    f = fournisseur()
    statut, erreur = "envoye", None
    try:
        resultat = await f.envoyer(
            destinataire=destinataire,
            objet=objet,
            html=html,
            texte=texte,
            expediteur=settings.mail_expediteur,
        )
        if resultat.brut.get("simule"):
            statut = "simule"
    except ErreurCourriel as exc:
        statut, erreur = "echec", exc.message
        log.warning("Courriel %r vers %s en échec : %s", code, destinataire, exc.message)
    except Exception as exc:  # noqa: BLE001
        statut, erreur = "echec", str(exc)[:500]
        log.exception("Courriel %r vers %s : erreur inattendue.", code, destinataire)

    try:
        await execute(
            """insert into email_log (template, user_id, destinataire, objet, statut, erreur, sent_at)
               values (%s, %s, %s, %s, %s, %s, case when %s in ('envoye','simule') then now() end)""",
            (code, user_id, destinataire, objet, statut, erreur, statut),
        )
    except Exception:  # noqa: BLE001
        # La trace a échoué, pas l'envoi. On ne perd pas le message pour autant.
        log.exception("Journalisation du courriel %r impossible.", code)

    return statut


async def deja_envoye(code: str, user_id: str, depuis_heures: int) -> bool:
    """Vrai si ce message est déjà parti à cette personne récemment.

    Sert aux rappels d'échéance, que l'ordonnanceur repasse toutes les heures :
    sans ce garde-fou, un abonné à sept jours du terme recevrait vingt-quatre
    rappels par jour.
    """
    try:
        ligne = await fetch_one(
            """select 1 from email_log
                where template = %s and user_id = %s and statut in ('envoye','simule')
                  and created_at > now() - make_interval(hours => %s) limit 1""",
            (code, user_id, depuis_heures),
        )
        return bool(ligne)
    except Exception:  # noqa: BLE001
        log.exception("Vérification d'envoi antérieur impossible.")
        # Dans le doute, on ne renvoie pas : un doublon dérange plus qu'un oubli.
        return True
