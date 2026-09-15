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
4. **Ce qui peut repartir repart.** Une panne passagère (Brevo lent, débit
   limité, disjoncteur ouvert) met le message en file : il garde de quoi être
   renvoyé et une date de prochaine tentative, jusqu'à cinq essais espacés de
   1 min à 6 h. Un refus définitif (adresse invalide) ne se rejoue pas.
"""
import json
import logging

from app.core.config import settings
from app.core.db import connection, execute, fetch_one
from app.services.resilience import prochaine_tentative

from .base import ErreurCourriel
from .brevo import Brevo
from .gabarit import envelopper, rendre

log = logging.getLogger("ascenda.courriel")

# Jamais mis en file : leur contexte porte un secret (le code de réinitialisation
# en clair), que la base ne garde par ailleurs que haché. Le lecteur redemande.
SANS_FILE = {"mot_de_passe_oublie"}

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

    objet, html, texte = _composer(code, gabarit, contexte)
    statut, erreur, rejouable = await _expedier(code, destinataire, objet, html, texte)

    try:
        a_reprendre = statut == "echec" and rejouable and code not in SANS_FILE
        await execute(
            """insert into email_log (template, user_id, destinataire, objet, statut, erreur, sent_at,
                                      tentatives, prochaine_tentative, contexte)
               values (%s, %s, %s, %s, %s, %s, case when %s in ('envoye','simule') then now() end,
                       1, %s, %s::jsonb)""",
            (code, user_id, destinataire, objet, statut, erreur, statut,
             prochaine_tentative(1) if a_reprendre else None,
             json.dumps(contexte, ensure_ascii=False, default=str) if a_reprendre else None),
        )
    except Exception:  # noqa: BLE001
        # La trace a échoué, pas l'envoi. On ne perd pas le message pour autant.
        log.exception("Journalisation du courriel %r impossible.", code)

    return statut


def _composer(code: str, gabarit: dict, contexte: dict) -> tuple[str, str, str]:
    objet = rendre(gabarit["objet"], contexte)
    corps = rendre(gabarit["corps_html"], contexte)
    html = envelopper(code, objet, corps)
    texte = rendre(gabarit["corps_texte"] or "", contexte) or _texte_de_secours(corps)
    return objet, html, texte


async def _expedier(code: str, destinataire: str, objet: str, html: str, texte: str
                    ) -> tuple[str, str | None, bool]:
    """(statut, erreur, rejouable). Ne lève jamais."""
    try:
        resultat = await fournisseur().envoyer(
            destinataire=destinataire, objet=objet, html=html, texte=texte,
            expediteur=settings.mail_expediteur,
        )
        return ("simule" if resultat.brut.get("simule") else "envoye"), None, False
    except ErreurCourriel as exc:
        log.warning("Courriel %r vers %s en échec : %s", code, destinataire, exc.message)
        return "echec", exc.message, exc.rejouable
    except Exception as exc:  # noqa: BLE001
        log.exception("Courriel %r vers %s : erreur inattendue.", code, destinataire)
        return "echec", str(exc)[:500], True


async def reprendre(limite: int = 20) -> dict:
    """Renvoie les courriels en file dont l'heure est venue.

    Les lignes sont réservées par `for update skip locked` et leur prochaine
    tentative repoussée de dix minutes dans la même transaction : deux instances
    qui passent ensemble ne renvoient jamais le même message, et une instance qui
    meurt en plein envoi le rend à la file dix minutes plus tard.
    """
    async with connection() as conn:
        cur = await conn.execute(
            """update email_log set prochaine_tentative = now() + interval '10 minutes'
                where id in (select id from email_log
                              where statut = 'echec' and prochaine_tentative <= now()
                              order by prochaine_tentative limit %s
                              for update skip locked)
            returning id, template, destinataire, contexte, tentatives""",
            (limite,),
        )
        lignes = await cur.fetchall()

    bilan = {"repris": len(lignes), "envoyes": 0, "en_file": 0, "abandonnes": 0}
    for l in lignes:
        gabarit = await fetch_one(
            "select code, objet, corps_html, corps_texte, actif from email_template where code = %s",
            (l["template"],),
        )
        if not gabarit or not gabarit["actif"] or not l["contexte"]:
            await execute("update email_log set statut = 'abandonne', prochaine_tentative = null where id = %s",
                          (l["id"],))
            bilan["abandonnes"] += 1
            continue
        objet, html, texte = _composer(l["template"], gabarit, l["contexte"])
        statut, erreur, rejouable = await _expedier(l["template"], l["destinataire"], objet, html, texte)
        tentatives = l["tentatives"] + 1
        if statut in ("envoye", "simule"):
            await execute(
                """update email_log set statut = %s, erreur = null, sent_at = now(), tentatives = %s,
                          prochaine_tentative = null where id = %s""",
                (statut, tentatives, l["id"]),
            )
            bilan["envoyes"] += 1
            continue
        suivante = prochaine_tentative(tentatives) if rejouable else None
        await execute(
            """update email_log set statut = %s, erreur = %s, tentatives = %s, prochaine_tentative = %s
                where id = %s""",
            ("echec" if suivante else "abandonne", erreur, tentatives, suivante, l["id"]),
        )
        bilan["en_file" if suivante else "abandonnes"] += 1
    return bilan


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
