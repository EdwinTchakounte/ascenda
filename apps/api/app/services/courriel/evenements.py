"""Les moments où ASCENDA écrit à quelqu'un.

Un seul endroit pour cinq messages. Les appelants (l'inscription, le paiement,
l'ordonnanceur) n'ont pas à savoir comment on formate un montant ni une date :
ils annoncent ce qui vient de se produire.
"""
import logging
from datetime import datetime

from app.core.db import fetch_all, fetch_one

from .service import deja_envoye, envoyer

log = logging.getLogger("ascenda.courriel.evenements")

_MOIS = ("janvier", "février", "mars", "avril", "mai", "juin", "juillet",
         "août", "septembre", "octobre", "novembre", "décembre")

# Sous ce seuil, on prévient. Sept jours laissent le temps de renouveler sans
# que l'accès se referme entre deux séances de lecture.
JOURS_RAPPEL = 7
# L'ordonnanceur repasse toutes les heures. Sans ce garde-fou, un abonné à sept
# jours du terme recevrait vingt-quatre rappels par jour.
FENETRE_RAPPEL_HEURES = 20


def date_fr(d: datetime | None) -> str:
    if not d:
        return "une date à confirmer"
    return f"{d.day} {_MOIS[d.month - 1]} {d.year}"


def montant_fr(valeur: int | None, devise: str = "XAF") -> str:
    """28000 devient « 28 000 XAF ». Une espace insécable : un montant ne se
    coupe pas en fin de ligne."""
    s = str(int(valeur or 0))
    morceaux = []
    for i, c in enumerate(s):
        if i > 0 and (len(s) - i) % 3 == 0:
            morceaux.append(" ")
        morceaux.append(c)
    return "".join(morceaux) + f" {devise}"


def _prenom(nom: str | None, email: str | None) -> str:
    """Le prénom, ou à défaut quelque chose qui ne sonne pas comme un publipostage.

    Écrire « Bonjour ,  » parce que le nom est vide est le premier signe qu'un
    message est automatique et mal fini.
    """
    if nom and nom.strip():
        return nom.strip().split()[0]
    return "et bienvenue"


async def bienvenue(user: dict) -> str:
    if not user.get("email"):
        return "ignore"
    return await envoyer(
        "bienvenue",
        destinataire=user["email"],
        user_id=str(user["id"]),
        contexte={"prenom": _prenom(user.get("display_name"), user.get("email"))},
    )


async def paiement_confirme(paiement: dict, abonnement: dict | None) -> str:
    u = await fetch_one("select id, email, display_name from app_user where id = %s",
                        (paiement["user_id"],))
    if not u or not u["email"]:
        return "ignore"
    return await envoyer(
        "paiement_confirme",
        destinataire=u["email"],
        user_id=str(u["id"]),
        contexte={
            "prenom": _prenom(u["display_name"], u["email"]),
            "montant": montant_fr(paiement.get("montant"), paiement.get("devise") or "XAF"),
            "periode": paiement.get("periode_mois") or 1,
            "fin": date_fr((abonnement or {}).get("current_end")),
            # La référence du fournisseur si nous l'avons, sinon la nôtre :
            # dans les deux cas elle permet de retrouver la trace.
            "reference": paiement.get("reference_externe") or str(paiement["id"])[:8],
        },
    )


async def paiement_rejete(paiement: dict) -> str:
    u = await fetch_one("select id, email, display_name from app_user where id = %s",
                        (paiement["user_id"],))
    if not u or not u["email"]:
        return "ignore"
    return await envoyer(
        "paiement_rejete",
        destinataire=u["email"],
        user_id=str(u["id"]),
        contexte={
            "prenom": _prenom(u["display_name"], u["email"]),
            "montant": montant_fr(paiement.get("montant"), paiement.get("devise") or "XAF"),
            "motif": paiement.get("motif_rejet") or "non précisée par l'opérateur",
        },
    )


async def abonnement_echu(user_id: str, fin: datetime | None) -> str:
    u = await fetch_one("select id, email, display_name from app_user where id = %s", (user_id,))
    if not u or not u["email"]:
        return "ignore"
    return await envoyer(
        "abonnement_echu",
        destinataire=u["email"],
        user_id=str(u["id"]),
        contexte={"prenom": _prenom(u["display_name"], u["email"]), "fin": date_fr(fin)},
    )


async def rappels_echeance() -> dict:
    """Prévient ceux dont l'accès se referme sous une semaine.

    Appelé par l'ordonnanceur. Ne lève jamais : un rappel manqué ne doit pas
    empêcher la fermeture des abonnements échus, qui tourne dans le même cycle.
    """
    bilan = {"candidats": 0, "envoyes": 0, "deja": 0}
    try:
        lignes = await fetch_all(
            """select s.user_id, s.current_end, u.email, u.display_name
                 from subscription s join app_user u on u.id = s.user_id
                where s.status = 'active'
                  and s.current_end > now()
                  and s.current_end <= now() + make_interval(days => %s)
                  and u.email is not null""",
            (JOURS_RAPPEL,),
        )
    except Exception:  # noqa: BLE001
        log.exception("Recherche des abonnements proches de l'échéance impossible.")
        return bilan

    from datetime import timezone

    bilan["candidats"] = len(lignes)
    for a in lignes:
        uid = str(a["user_id"])
        if await deja_envoye("abonnement_bientot_echu", uid, FENETRE_RAPPEL_HEURES):
            bilan["deja"] += 1
            continue
        jours = max(0, (a["current_end"] - datetime.now(timezone.utc)).days)
        statut = await envoyer(
            "abonnement_bientot_echu",
            destinataire=a["email"],
            user_id=uid,
            contexte={
                "prenom": _prenom(a["display_name"], a["email"]),
                "jours": jours,
                "fin": date_fr(a["current_end"]),
            },
        )
        if statut in ("envoye", "simule"):
            bilan["envoyes"] += 1
    return bilan
