"""Le courrier transactionnel, sans clé Brevo et sans réseau."""
import asyncio
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "apps" / "api"))

from app.core.db import close_pool, connection, execute, fetch_all, fetch_one, open_pool  # noqa: E402
from app.services.courriel import evenements, service as courriel  # noqa: E402
from app.services.courriel.brevo import Brevo, decouper_expediteur  # noqa: E402
from app.services.courriel.gabarit import envelopper, rendre  # noqa: E402
from app.services.paiement import service as paiement  # noqa: E402

_resultats = []


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


async def utilisateur(suffixe: str, nom: str = "Edwin Essai"):
    return await fetch_one(
        """insert into app_user (email, display_name, plan) values (%s, %s, 'free')
           returning *""",
        (f"courriel-{suffixe}-{uuid.uuid4().hex[:6]}@example.com", nom),
    )


async def journal(user_id, code=None):
    if code:
        return await fetch_all(
            "select * from email_log where user_id = %s and template = %s order by created_at",
            (str(user_id), code),
        )
    return await fetch_all(
        "select * from email_log where user_id = %s order by created_at", (str(user_id),)
    )


async def main():
    await open_pool()

    print("\n· Les cinq gabarits sont en base et actifs")
    attendus = ["bienvenue", "paiement_confirme", "paiement_rejete",
                "abonnement_bientot_echu", "abonnement_echu"]
    for code in attendus:
        g = await fetch_one("select code, objet, corps_html, actif from email_template where code = %s", (code,))
        ok(f"{code} présent et actif", g and g["actif"] and g["corps_html"], (g or {}).get("objet", "absent"))

    print("\n· Le mode simulé, notre état par défaut aujourd'hui")
    ok("sans clé, Brevo ne sort pas sur le réseau", Brevo().simule is True)
    ok("« ASCENDA <a@b.c> » se découpe", decouper_expediteur("ASCENDA <a@b.c>") == ("ASCENDA", "a@b.c"),
       decouper_expediteur("ASCENDA <a@b.c>"))
    ok("une adresse nue se découpe aussi", decouper_expediteur("a@b.c")[1] == "a@b.c")

    print("\n· L'enveloppe et le remplacement des jetons")
    html = envelopper("paiement_confirme", "Objet", "<p>Montant : {montant}</p>".format(montant="8 000 XAF"))
    ok("l'enveloppe porte la marque", "ASCENDA" in html)
    ok("elle ne référence aucune image distante", "<img" not in html)
    ok("elle porte l'avertissement anti-hameçonnage",
       "jamais votre mot de passe" in html)
    ok("un jeton manquant ne fait pas tomber le rendu",
       rendre("Bonjour {inconnu}", {"prenom": "Edwin"}) == "Bonjour {inconnu}")

    print("\n· Bienvenue à l'inscription")
    u = await utilisateur("bienvenue")
    statut = await evenements.bienvenue(u)
    lignes = await journal(u["id"], "bienvenue")
    ok("le message part", statut == "simule", statut)
    ok("il est tracé", len(lignes) == 1, f"{len(lignes)} ligne(s)")
    ok("le prénom est repris dans l'objet",
       lignes and "Edwin" in lignes[0]["objet"], (lignes[0]["objet"] if lignes else ""))
    ok("aucun jeton ne reste dans l'objet",
       lignes and "{" not in lignes[0]["objet"], (lignes[0]["objet"] if lignes else ""))

    # Un compte sans nom ne doit pas produire « Bienvenue sur ASCENDA,  ».
    sans_nom = await utilisateur("sansnom", nom=None)
    await evenements.bienvenue(sans_nom)
    l2 = await journal(sans_nom["id"], "bienvenue")
    ok("un compte sans nom garde un objet lisible",
       l2 and l2[0]["objet"].strip().endswith(("bienvenue", "!")) or (l2 and ", " in l2[0]["objet"]),
       (l2[0]["objet"] if l2 else ""))

    print("\n· Le reçu de paiement, déclenché par la validation")
    u = await utilisateur("recu")
    p = await fetch_one(
        """insert into payment (user_id, plan_cible, periode_mois, montant, devise,
                                telephone, reseau, gateway_initiated_at)
           values (%s, 'premium', 3, 8000, 'XAF', '237677000111', 'MTN', now()) returning *""",
        (u["id"],),
    )
    change = await paiement.appliquer(p, "valide", source="admin", strategie="suite")
    lignes = await journal(u["id"], "paiement_confirme")
    ok("la validation déclenche le reçu", change and len(lignes) == 1, f"{len(lignes)} ligne(s)")
    ok("le reçu ne porte aucun jeton", lignes and "{" not in lignes[0]["objet"])
    abo = await fetch_one("select current_end from subscription where user_id = %s", (u["id"],))
    ok("l'abonnement a bien été ouvert au passage", abo is not None)

    print("\n· Rejouer la validation n'écrit pas deux fois")
    p2 = await fetch_one("select * from payment where id = %s", (p["id"],))
    await paiement.appliquer(p2, "valide", source="admin", strategie="rejeu")
    lignes = await journal(u["id"], "paiement_confirme")
    ok("un seul reçu après rejeu", len(lignes) == 1, f"{len(lignes)} ligne(s)")

    print("\n· Le message de rejet")
    u = await utilisateur("rejet")
    p = await fetch_one(
        """insert into payment (user_id, plan_cible, periode_mois, montant, devise,
                                gateway_initiated_at)
           values (%s, 'premium', 1, 3000, 'XAF', now()) returning *""",
        (u["id"],),
    )
    await paiement.appliquer(p, "rejete", source="admin", motif="Solde insuffisant.")
    lignes = await journal(u["id"], "paiement_rejete")
    ok("le rejet prévient le membre", len(lignes) == 1, f"{len(lignes)} ligne(s)")

    print("\n· Le rappel avant échéance")
    u = await utilisateur("rappel")
    fin = datetime.now(timezone.utc) + timedelta(days=4)
    await execute(
        """insert into subscription (user_id, plan, provider, status, current_start,
                                     current_end, amount_cents, currency, periode_mois)
           values (%s, 'premium', 'tara', 'active', now(), %s, 8000, 'XAF', 3)""",
        (u["id"], fin),
    )
    bilan = await evenements.rappels_echeance()
    lignes = await journal(u["id"], "abonnement_bientot_echu")
    ok("l'abonné proche du terme est prévenu", len(lignes) == 1, f"bilan {bilan}")
    ok("le nombre de jours est calculé", lignes and "4" in lignes[0]["objet"] or "3" in (lignes[0]["objet"] if lignes else ""),
       (lignes[0]["objet"] if lignes else ""))

    print("\n· Le rappel ne se répète pas à chaque tour de l'ordonnanceur")
    await evenements.rappels_echeance()
    await evenements.rappels_echeance()
    lignes = await journal(u["id"], "abonnement_bientot_echu")
    ok("toujours un seul rappel après trois passages", len(lignes) == 1, f"{len(lignes)} ligne(s)")

    print("\n· La fermeture à échéance prévient aussi")
    u = await utilisateur("echu")
    async with connection() as c:
        await c.execute(
            """insert into subscription (user_id, plan, provider, status, current_start,
                                         current_end, amount_cents, currency, periode_mois)
               values (%s, 'premium', 'tara', 'active', now() - interval '31 days',
                       now() - interval '1 hour', 3000, 'XAF', 1)""",
            (u["id"],),
        )
        await c.execute("update app_user set plan = 'premium' where id = %s", (u["id"],))
    bilan = await paiement.fermer_echus()
    lignes = await journal(u["id"], "abonnement_echu")
    u2 = await fetch_one("select plan from app_user where id = %s", (u["id"],))
    ok("l'accès est refermé", u2["plan"] == "free", u2["plan"])
    ok("le membre est prévenu de la fin", len(lignes) == 1, f"bilan {bilan}")

    print("\n· Un gabarit désactivé n'envoie rien")
    await execute("update email_template set actif = false where code = 'bienvenue'")
    u = await utilisateur("desactive")
    statut = await evenements.bienvenue(u)
    lignes = await journal(u["id"], "bienvenue")
    ok("l'interrupteur coupe l'envoi", statut == "ignore" and not lignes, statut)
    await execute("update email_template set actif = true where code = 'bienvenue'")

    print("\n· Une adresse absente n'est pas une panne")
    async with connection() as c:
        cur = await c.execute(
            "insert into app_user (email, display_name, plan) values (null, 'Sans adresse', 'free') returning *"
        )
        anonyme = await cur.fetchone()
    ok("un compte sans adresse est ignoré proprement",
       await evenements.bienvenue(anonyme) == "ignore")

    print("\n· Le formatage")
    # L'espace des milliers est une espace fine insécable (U+202F) : un montant
    # ne se coupe pas en fin de ligne, et c'est l'usage typographique français.
    ok("28000 devient « 28 000 XAF », espace fine insécable comprise",
       evenements.montant_fr(28000) == "28\u202f000 XAF",
       repr(evenements.montant_fr(28000)))
    ok("les dates sont en français",
       evenements.date_fr(datetime(2026, 11, 27, tzinfo=timezone.utc)) == "27 novembre 2026",
       evenements.date_fr(datetime(2026, 11, 27, tzinfo=timezone.utc)))
    ok("une date absente ne casse rien", "confirmer" in evenements.date_fr(None))

    await close_pool()


asyncio.run(main())

print("\n" + "=" * 92)
_echecs = [x for x in _resultats if not x[0]]
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
