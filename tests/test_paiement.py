"""Vérifie les trois stratégies de rattachement et la fermeture à échéance."""
import asyncio, json, sys, uuid
from datetime import datetime, timedelta, timezone
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1] / "apps" / "api"))
from app.core.db import open_pool, close_pool, connection, fetch_one, fetch_all
from app.services.paiement import service
from app.services.paiement.base import EvenementWebhook

_resultats = []
def ok(l, c, e=""):
    _resultats.append((bool(c), l, str(e)))
    print(("  OUI  " if c else "  NON  ") + l + ("  " + str(e) if e else ""))

async def utilisateur(suffixe):
    return await fetch_one(
        """insert into app_user (email, display_name, plan) values (%s,%s,'free') returning *""",
        (f"rat-{suffixe}-{uuid.uuid4().hex[:6]}@example.com", "Test"))

async def paiement_en_attente(u, tel="237655000111"):
    p = await fetch_one(
        """insert into payment (user_id, periode_mois, montant, telephone, reseau,
                                gateway_initiated_at)
           values (%s, 1, 3000, %s, 'MTN', now()) returning *""", (u["id"], tel))
    return p

async def main():
    await open_pool()

    print("\n· Stratégie 1 : notre clé d'idempotence")
    u = await utilisateur("s1"); p = await paiement_en_attente(u)
    trouve, strat = await service.rattacher(EvenementWebhook(
        cle_idempotence=str(p["idempotency_key"]), statut="valide",
        reference_fournisseur="TARA-1", telephone="237655000111"))
    ok("rattache par cle_idempotence", trouve and str(trouve["id"])==str(p["id"]) and strat=="cle_idempotence", strat)

    print("\n· Stratégie 2 : la référence du fournisseur")
    u = await utilisateur("s2"); p = await paiement_en_attente(u, "237655000222")
    async with connection() as c:
        await c.execute("update payment set reference_externe='TARA-XYZ' where id=%s", (p["id"],))
    trouve, strat = await service.rattacher(EvenementWebhook(
        cle_idempotence="", statut="valide", reference_fournisseur="TARA-XYZ", telephone=None))
    ok("rattache par reference_externe", trouve and str(trouve["id"])==str(p["id"]) and strat=="reference_externe", strat)

    print("\n· Stratégie 3 : le téléphone, cas réel où Tara ne renvoie pas notre productId")
    u = await utilisateur("s3"); p = await paiement_en_attente(u, "237699888777")
    trouve, strat = await service.rattacher(EvenementWebhook(
        cle_idempotence="991234", statut="valide",
        reference_fournisseur="TARA-2", telephone="699888777"))
    ok("rattache par telephone recent", trouve and str(trouve["id"])==str(p["id"]) and strat=="telephone_recent", strat)

    print("\n· Le téléphone ancien ne rattache pas")
    u = await utilisateur("s4"); p = await paiement_en_attente(u, "237699111222")
    async with connection() as c:
        await c.execute("update payment set created_at = now() - interval '2 hours' where id=%s", (p["id"],))
    trouve, strat = await service.rattacher(EvenementWebhook(
        cle_idempotence="x", statut="valide", reference_fournisseur="y", telephone="699111222"))
    ok("hors fenetre de 30 min : non rattache", trouve is None, strat)

    print("\n· Idempotence : rejouer le webhook ne crédite pas deux fois")
    u = await utilisateur("idem"); p = await paiement_en_attente(u, "237691234567")
    corps = json.dumps({"productId": str(p["idempotency_key"]), "status": "SUCCESS",
                        "paymentId": "TARA-IDEM", "phoneNumber": "237691234567"}).encode()
    r1 = await service.traiter_webhook(corps)
    r2 = await service.traiter_webhook(corps)
    a = await fetch_all("select * from subscription where user_id=%s", (u["id"],))
    ok("premier webhook traite", r1["traite"] is True, r1["strategie"])
    ok("second webhook sans effet", r2["traite"] is False)
    ok("un seul abonnement cree", len(a)==1, f"{len(a)} abonnement(s)")
    fin1 = a[0]["current_end"]
    ok("fin d'abonnement inchangee", (fin1 - datetime.now(timezone.utc)).days in (29,30), f"{(fin1-datetime.now(timezone.utc)).days} jours")

    print("\n· Un paiement valide ne redevient pas rejete")
    corps_rejet = json.dumps({"productId": str(p["idempotency_key"]), "status": "FAILED",
                              "paymentId": "TARA-IDEM"}).encode()
    r3 = await service.traiter_webhook(corps_rejet)
    pf = await fetch_one("select statut from payment where id=%s", (p["id"],))
    ok("statut protege", pf["statut"]=="valide" and r3["traite"] is False, pf["statut"])

    print("\n· Prolongation : payer avant l'echeance n'efface pas les jours restants")
    p2 = await paiement_en_attente(u, "237691234567")
    async with connection() as c:
        await c.execute("update payment set periode_mois=1 where id=%s", (p2["id"],))
    p2 = await fetch_one("select * from payment where id=%s", (p2["id"],))
    await service.ouvrir_abonnement(p2)
    a2 = await fetch_one("select * from subscription where user_id=%s order by current_end desc", (u["id"],))
    ok("abonnement prolonge, pas remplace", (a2["current_end"] - fin1).days == 30, f"+{(a2['current_end']-fin1).days} jours")

    print("\n· Fermeture a echeance")
    u = await utilisateur("exp")
    async with connection() as c:
        await c.execute("""insert into subscription (user_id, plan, status, current_start,
                             current_end, periode_mois) values (%s,'premium','active',
                             now() - interval '31 days', now() - interval '1 hour', 1)""", (u["id"],))
        await c.execute("update app_user set plan='premium' where id=%s", (u["id"],))
    bilan = await service.fermer_echus()
    apres = await fetch_one("select plan from app_user where id=%s", (u["id"],))
    ok("abonnement echu ferme", bilan["expires"]>=1, bilan)
    ok("acces referme, compte en free", apres["plan"]=="free", apres["plan"])

    print("\n· Reconciliation : abandon apres 24 h")
    u = await utilisateur("timeout"); p = await paiement_en_attente(u, "237690000001")
    async with connection() as c:
        await c.execute("""update payment set gateway_initiated_at = now() - interval '30 hours'
                           where id=%s""", (p["id"],))
    bilan = await service.reconcilier(taille=200, pause=0)
    pf = await fetch_one("select statut, motif_rejet from payment where id=%s", (p["id"],))
    ok("paiement abandonne", pf["statut"]=="rejete", pf["motif_rejet"])

    await close_pool()

asyncio.run(main())

_echecs = [x for x in _resultats if not x[0]]
# ------------------------------------------------------------------ la caisse
# fermée. Sans identifiants Tara, le fournisseur renvoie une référence factice.
# En production, cela donnerait à un lecteur le sentiment d'avoir payé sans
# qu'aucune demande ne parte vers son téléphone. Le service doit refuser.
async def _caisse_fermee():
    import app.core.config as conf
    from app.services.paiement import service as paie
    from app.core.errors import Conflict

    vrai = conf.settings.api_env
    try:
        conf.settings.api_env = "prod"
        from app.services.paiement.tara import Tara
        ok("sans clé, le fournisseur est bien en mode simulé", Tara().simule)
        try:
            await paie.initier({"id": "0" * 36, "provider_code": "tara",
                                "plan_cible": "premium", "periode_mois": 1,
                                "idempotency_key": "essai"}, "690000000", "mtn")
            ok("en production, une caisse sans clé refuse d'initier", False,
               "aucune erreur levée : un paiement factice serait parti")
        except Conflict as exc:
            ok("en production, une caisse sans clé refuse d'initier",
               "pas encore ouvert" in str(exc.message if hasattr(exc, "message") else exc))
    finally:
        conf.settings.api_env = vrai


asyncio.run(_caisse_fermee())

print("\n" + "=" * 92)
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
