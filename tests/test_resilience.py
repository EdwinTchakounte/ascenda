"""Vérifie que ce qui échoue se reprend, et que ce qui reste en panne se signale.

- le disjoncteur : ouverture au seuil, refus sans appel, essai unique, refermeture ;
- un refus métier ne coupe pas le service pour tout le monde ;
- les reprises espacées d'une lecture, et jamais d'une opération non rejouable ;
- la file des courriels : panne passagère, renvoi, abandon au cinquième essai ;
- un secret n'est jamais mis en file ;
- un travail orphelin est remis en file, puis abandonné ;
- la veille : un incident ouvert une fois, une seule alerte, refermé avec son avis ;
- la sauvegarde trop ancienne ouvre un incident ;
- la sonde de santé.
"""
import asyncio, sys, uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps" / "api"))
import httpx  # noqa: E402

from app.core.db import open_pool, close_pool, execute, fetch_all, fetch_one  # noqa: E402
from app.services import resilience, veille  # noqa: E402
from app.services.courriel import service as courriel  # noqa: E402
from app.services.courriel.base import ErreurCourriel, ResultatEnvoi  # noqa: E402
from app.services.courriel.brevo import Brevo  # noqa: E402
from app.services.resilience import CircuitOuvert, Disjoncteur  # noqa: E402

API = __import__("os").getenv("ASCENDA_API", "http://127.0.0.1:8250")

_resultats = []
def ok(l, c, e=""):
    _resultats.append((bool(c), l, str(e)))
    print(("  OUI  " if c else "  NON  ") + l + ("  " + str(e) if e else ""))


class Horloge:
    def __init__(self):
        self.t = 1000.0
    def __call__(self):
        return self.t


async def disjoncteur():
    print("\n· Le disjoncteur")
    h = Horloge()
    d = Disjoncteur("essai", seuil=3, pause=60, horloge=h)
    appels = 0

    async def en_panne():
        nonlocal appels
        appels += 1
        raise TimeoutError("délai dépassé")

    async def repond():
        nonlocal appels
        appels += 1
        return "ok"

    for _ in range(3):
        try:
            await d.appeler(en_panne)
        except TimeoutError:
            pass
    ok("ouvert après trois échecs d'affilée", d.vue()["etat"] == "ouvert", d.vue()["etat"])

    avant = appels
    try:
        await d.appeler(repond)
        ok("ouvert, il refuse sans appeler le service", False, "l'appel est passé")
    except CircuitOuvert as exc:
        ok("ouvert, il refuse sans appeler le service", appels == avant, f"nouvel essai dans {round(exc.reessayer_dans)} s")

    h.t += 61
    ok("après la pause, il passe demi-ouvert", d.vue()["etat"] == "demi_ouvert")
    d.avant_appel()  # l'appel d'essai est pris
    try:
        d.avant_appel()
        ok("demi-ouvert, un seul appel d'essai à la fois", False)
    except CircuitOuvert:
        ok("demi-ouvert, un seul appel d'essai à la fois", True)
    d.echec("toujours en panne")
    ok("essai raté : il repart pour une pause entière", d.vue()["etat"] == "ouvert" and d.vue()["reessai_dans_s"] == 60,
       d.vue())

    h.t += 61
    r = await d.appeler(repond)
    ok("essai réussi : il se referme", r == "ok" and d.vue()["etat"] == "ferme" and d.echecs == 0)
    ok("les coupures sont comptées", d.ouvertures == 2, d.ouvertures)

    print("\n· Un refus métier ne coupe pas le service")
    d2 = Disjoncteur("metier", seuil=2, pause=60, horloge=h)

    async def refus():
        raise ErreurCourriel("adresse invalide", rejouable=False)

    for _ in range(5):
        try:
            await d2.appeler(refus, compte_comme_echec=lambda exc: getattr(exc, "rejouable", True))
        except ErreurCourriel:
            pass
    ok("cinq adresses invalides laissent le disjoncteur fermé", d2.vue()["etat"] == "ferme", d2.vue())

    print("\n· Les reprises espacées")
    essais = 0

    async def instable():
        nonlocal essais
        essais += 1
        if essais < 3:
            raise httpx.ConnectError("coupé")
        return "lu"

    r = await resilience.avec_reprises(instable, essais=3, base=0.01)
    ok("une lecture instable réussit au troisième essai", r == "lu" and essais == 3, essais)

    essais = 0

    async def refus_definitif():
        nonlocal essais
        essais += 1
        raise ValueError("numéro invalide")

    try:
        await resilience.avec_reprises(refus_definitif, essais=3, base=0.01, rejouable=lambda exc: False)
    except ValueError:
        pass
    ok("un refus non rejouable n'est tenté qu'une fois", essais == 1, essais)

    maintenant = datetime.now(timezone.utc)
    ecarts = [(resilience.prochaine_tentative(n, maintenant) - maintenant).total_seconds() for n in range(1, 6)]
    bornes = [60, 300, 1800, 7200, 21600]
    ok("paliers 1 min, 5 min, 30 min, 2 h, 6 h, à 10 % près",
       all(b * 0.9 <= e <= b * 1.1 for e, b in zip(ecarts, bornes)), [round(e) for e in ecarts])
    ok("après le cinquième échec : abandon", resilience.prochaine_tentative(6, maintenant) is None)

    print("\n· Tara : le disjoncteur de la caisse")
    from app.services.paiement import tara as module_tara
    from app.services.paiement.base import ErreurFournisseur
    ok("Tara coupe après 3 échecs, pour 2 min", resilience.DISJONCTEURS["tara"].seuil == 3
       and resilience.DISJONCTEURS["tara"].pause == 120)
    source = Path(module_tara.__file__).read_text()
    ok("l'initiation d'un paiement n'est jamais rejouée", "avec_reprises" not in source.split("def initier")[1].split("\n    async def ")[0]
       if "def initier" in source else False)
    ok("ErreurFournisseur porte le drapeau rejouable", "rejouable" in ErreurFournisseur.__init__.__code__.co_varnames)


async def file_courriels():
    print("\n· La file des courriels")
    ancien = courriel._fournisseur
    b = Brevo()
    b.cle = "cle-de-test"
    etat = {"panne": True, "appels": 0}

    async def poster(charge):
        etat["appels"] += 1
        if etat["panne"]:
            raise ErreurCourriel("Brevo en erreur serveur (503).", rejouable=True)
        return ResultatEnvoi(reference="msg-1", brut={})

    b._poster = poster
    courriel._fournisseur = b
    resilience.DISJONCTEURS["brevo"].succes()
    dest = f"file-{uuid.uuid4().hex[:6]}@example.com"
    try:
        statut = await courriel.envoyer("bienvenue", destinataire=dest, contexte={"prenom": "Awa"})
        l = await fetch_one("select * from email_log where destinataire = %s", (dest,))
        ok("panne passagère : le message est en file", statut == "echec" and l["prochaine_tentative"] is not None
           and l["contexte"] and l["contexte"].get("prenom") == "Awa", l and l["statut"])

        await execute("update email_log set prochaine_tentative = now() - interval '1 second' where id = %s", (l["id"],))
        etat["panne"] = False
        bilan = await courriel.reprendre()
        l = await fetch_one("select * from email_log where id = %s", (l["id"],))
        ok("Brevo revenu : le message repart", l["statut"] == "envoye" and l["tentatives"] == 2
           and l["prochaine_tentative"] is None, bilan)

        bilan = await courriel.reprendre()
        ok("un message parti ne repart pas", etat["appels"] == 2, etat["appels"])

        print("\n· Abandon au cinquième essai")
        etat["panne"] = True
        resilience.DISJONCTEURS["brevo"].succes()
        dest2 = f"abandon-{uuid.uuid4().hex[:6]}@example.com"
        await courriel.envoyer("bienvenue", destinataire=dest2, contexte={"prenom": "Paul"})
        l = await fetch_one("select * from email_log where destinataire = %s", (dest2,))
        for _ in range(5):
            resilience.DISJONCTEURS["brevo"].succes()
            await execute("update email_log set prochaine_tentative = now() - interval '1 second' where id = %s and statut = 'echec'",
                          (l["id"],))
            await courriel.reprendre()
        l = await fetch_one("select * from email_log where id = %s", (l["id"],))
        ok("après cinq échecs, le message est abandonné", l["statut"] == "abandonne" and l["prochaine_tentative"] is None,
           f"{l['statut']}, {l['tentatives']} tentatives")

        print("\n· Deux passages simultanés ne renvoient pas deux fois")
        etat.update(panne=True, appels=0)
        resilience.DISJONCTEURS["brevo"].succes()
        dest3 = f"double-{uuid.uuid4().hex[:6]}@example.com"
        await courriel.envoyer("bienvenue", destinataire=dest3, contexte={"prenom": "Iné"})
        l = await fetch_one("select * from email_log where destinataire = %s", (dest3,))
        await execute("update email_log set prochaine_tentative = now() - interval '1 second' where id = %s", (l["id"],))
        etat.update(panne=False, appels=0)
        await asyncio.gather(courriel.reprendre(), courriel.reprendre())
        ok("un seul renvoi pour deux passages concurrents", etat["appels"] == 1, etat["appels"])

        print("\n· Un secret n'est jamais mis en file")
        etat["panne"] = True
        resilience.DISJONCTEURS["brevo"].succes()
        dest4 = f"secret-{uuid.uuid4().hex[:6]}@example.com"
        await courriel.envoyer("mot_de_passe_oublie", destinataire=dest4, contexte={"code": "482913"})
        l = await fetch_one("select * from email_log where destinataire = %s", (dest4,))
        ok("réinitialisation en échec : ni file ni contexte gardé",
           l is not None and l["prochaine_tentative"] is None and l["contexte"] is None, l and l["statut"])

        print("\n· Brevo coupé : on ne fait plus attendre personne")
        resilience.DISJONCTEURS["brevo"].succes()
        for i in range(5):
            await courriel.envoyer("bienvenue", destinataire=f"coupe-{i}-{uuid.uuid4().hex[:4]}@example.com",
                                   contexte={"prenom": "X"})
        avant = etat["appels"]
        dest5 = f"coupe-fin-{uuid.uuid4().hex[:6]}@example.com"
        statut = await courriel.envoyer("bienvenue", destinataire=dest5, contexte={"prenom": "Y"})
        l = await fetch_one("select * from email_log where destinataire = %s", (dest5,))
        ok("disjoncteur ouvert : pas d'appel, message en file",
           etat["appels"] == avant and statut == "echec" and l["prochaine_tentative"] is not None,
           f"{etat['appels'] - avant} appel(s)")
    finally:
        courriel._fournisseur = ancien
        resilience.DISJONCTEURS["brevo"].succes()
        await execute("delete from email_log where destinataire like any(array['file-%%','abandon-%%','double-%%','secret-%%','coupe-%%'])")


async def travaux_orphelins():
    print("\n· Les travaux orphelins")
    ids = []
    for reprises, battement in ((0, "10 minutes"), (2, "10 minutes"), (0, "30 seconds")):
        l = await fetch_one(
            f"""insert into travail (type, etat, started_at, battement, reprises, journal)
               values ('passages', 'en_cours', now() - interval '20 minutes', now() - interval '{battement}', %s, 'essai')
               returning id""", (reprises,))
        ids.append(l["id"])
    try:
        await veille._travaux_orphelins()
        lignes = {str(l["id"]): l for l in await fetch_all(
            "select id, etat, reprises, erreur, journal from travail where id = any(%s)", (ids,))}
        a, b, c = (lignes[str(i)] for i in ids)
        ok("ouvrier muet depuis 10 min : remis en file", a["etat"] == "en_attente" and a["reprises"] == 1, a["etat"])
        ok("le journal dit ce qui s'est passé", "travail orphelin" in (a["journal"] or ""))
        ok("déjà repris deux fois : abandonné, avec la raison", b["etat"] == "echec" and "Interrompu" in (b["erreur"] or ""),
           b["etat"])
        ok("un travail qui bat encore n'est pas touché", c["etat"] == "en_cours" and c["reprises"] == 0, c["etat"])
    finally:
        await execute("delete from travail where id = any(%s)", (ids,))


async def veille_incidents():
    print("\n· La veille : un incident, une alerte, un avis de fin")
    admin = await fetch_one(
        """insert into app_user (email, display_name, plan, est_admin) values (%s, 'Veille', 'free', true) returning *""",
        (f"veille-{uuid.uuid4().hex[:6]}@example.com",))
    cle = f"essai_{uuid.uuid4().hex[:6]}"
    panne = {"active": True}

    async def controle():
        if not panne["active"]:
            return []
        return [veille.Constat(cle, "critique", "Panne d'essai", "Explication d'essai.", {"n": 1})]

    vrais = veille.CONTROLES
    veille.CONTROLES = [controle]
    # La veille de l'API qui tourne passe elle aussi toutes les cinq minutes, avec
    # les vrais contrôles : elle refermerait l'incident d'essai. On prend son
    # verrou pour la durée du test, comme le ferait une seconde instance.
    import psycopg
    from app.core.config import settings
    from app.services.ordonnanceur import VERROU_VEILLE
    verrou = await psycopg.AsyncConnection.connect(settings.dsn, autocommit=True)
    await verrou.execute("select pg_advisory_lock(%s)", (VERROU_VEILLE,))
    try:
        r1 = await veille.passer()
        r2 = await veille.passer()
        r3 = await veille.passer()
        ouverts = await fetch_all("select * from incident where cle = %s", (cle,))
        alertes = await fetch_all("select * from email_log where destinataire = %s and template = 'alerte_exploitation'",
                                  (admin["email"],))
        ok("ouvert au premier passage", cle in r1["ouverts"], r1)
        ok("gardé ensuite, pas recréé", cle in r2["gardes"] and cle in r3["gardes"] and len(ouverts) == 1, len(ouverts))
        ok("une seule alerte pour trois passages", len(alertes) == 1, len(alertes))
        ok("l'objet dit la gravité et le problème", alertes and "critique" in alertes[0]["objet"]
           and "Panne d'essai" in alertes[0]["objet"], alertes and alertes[0]["objet"])

        panne["active"] = False
        r4 = await veille.passer()
        inc = await fetch_one("select * from incident where cle = %s", (cle,))
        fins = await fetch_all(
            """select * from email_log where destinataire = %s and template = 'alerte_resolue'
                and objet like '%%Panne d''essai%%'""", (admin["email"],))
        ok("problème disparu : incident refermé", cle in r4["refermes"] and inc["clos_le"] is not None)
        ok("un avis de fin, avec la durée", len(fins) == 1 and "Résolu" in fins[0]["objet"], len(fins))

        panne["active"] = True
        await veille.passer()
        tous = await fetch_all("select * from incident where cle = %s order by ouvert_le", (cle,))
        ok("la panne revient : un nouvel incident, l'ancien reste dans l'historique",
           len(tous) == 2 and tous[0]["clos_le"] and tous[1]["clos_le"] is None, len(tous))

        print("\n· Un contrôle cassé ne masque pas les autres")
        async def casse():
            raise RuntimeError("contrôle en panne")
        veille.CONTROLES = [casse, controle]
        r = await veille.passer()
        ok("le contrôle suivant est quand même passé", cle in r["gardes"], r)

        veille.CONTROLES = [casse]
        r = await veille.passer()
        encore = await fetch_one("select clos_le from incident where cle = %s and clos_le is null", (cle,))
        ok("passage incomplet : rien n'est refermé à tort", r.get("incomplet") and not r["refermes"] and encore, r)
    finally:
        veille.CONTROLES = vrais
        await verrou.execute("select pg_advisory_unlock(%s)", (VERROU_VEILLE,))
        await verrou.close()
        await execute("delete from incident where cle = %s", (cle,))
        await execute("delete from email_log where destinataire = %s", (admin["email"],))
        await execute("delete from app_user where id = %s", (admin["id"],))


async def controles_reels():
    print("\n· Les contrôles sur la base réelle")
    for c in veille.CONTROLES:
        try:
            r = await c()
            ok(f"{c.__name__} répond", isinstance(r, list), [x.cle for x in r])
        except Exception as exc:  # noqa: BLE001
            ok(f"{c.__name__} répond", False, exc)

    ligne = await fetch_one(
        "insert into sauvegarde (fichier, octets, fini_le) values ('essai.dump.gz', 1234, now() - interval '30 hours') returning id")
    try:
        existe = await fetch_one("select count(*) as n from sauvegarde where fini_le > now() - interval '26 hours'")
        if existe["n"] == 0:
            r = await veille._sauvegarde()
            ok("sauvegarde de 30 h : incident critique", r and r[0].cle == "sauvegarde_ancienne" and r[0].gravite == "critique",
               [x.titre for x in r])
        recente = await fetch_one("insert into sauvegarde (fichier, octets) values ('essai2.dump.gz', 1234) returning id")
        r = await veille._sauvegarde()
        ok("sauvegarde de la nuit : rien à signaler", r == [], r)
        await execute("delete from sauvegarde where id = %s", (recente["id"],))
    finally:
        await execute("delete from sauvegarde where id = %s", (ligne["id"],))

    e = await veille.etat()
    ok("l'état de santé rassemble tout", all(k in e for k in
       ("incidents", "disjoncteurs", "courriels", "travaux", "sauvegarde", "ordonnanceur")), list(e))


async def sonde():
    print("\n· La sonde de santé")
    async with httpx.AsyncClient(timeout=10) as c:
        r = await c.get(f"{API}/sante")
        d = r.json()
        ok("200 et base joignable", r.status_code == 200 and d["base"] == "ok", r.status_code)
        # Le second fournisseur de modèle a rejoint la liste : la sonde dit
        # l'état de chaque dépendance externe, et il y en a désormais quatre.
        ok("l'état des dépendances, sans détail",
           set(d.get("dependances", {})) == {"tara", "brevo", "anthropic", "openai"}
           and all(v in ("ferme", "ouvert", "demi_ouvert") for v in d["dependances"].values()), d.get("dependances"))
        r = await c.get(f"{API}/v1/admin/sante")
        ok("le détail est réservé à la console", r.status_code in (401, 403), r.status_code)


async def main():
    await open_pool()
    try:
        await disjoncteur()
        await file_courriels()
        await travaux_orphelins()
        await veille_incidents()
        await controles_reels()
        await sonde()
    finally:
        await close_pool()


asyncio.run(main())

_echecs = [x for x in _resultats if not x[0]]
print("\n" + "=" * 92)
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
