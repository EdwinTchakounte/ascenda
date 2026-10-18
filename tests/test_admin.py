"""Le tableau de bord d'exploitation, et surtout ce qu'il refuse."""
import asyncio
import sys
import uuid
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "apps" / "api"))
sys.path.insert(0, str(RACINE / "tests"))

from commun import appel, suffixe  # noqa: E402

from app.core.db import close_pool, execute, fetch_one, open_pool  # noqa: E402
from app.core.security import hash_password  # noqa: E402

_resultats = []
MDP = "MotDePasse123!"


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


async def compte(admin: bool):
    email = f"adm-{suffixe()}-{uuid.uuid4().hex[:4]}@example.com"
    await execute(
        """insert into app_user (email, display_name, password_hash, plan, est_admin)
           values (%s, 'Essai', %s, 'free', %s)""",
        (email, hash_password(MDP), admin),
    )
    code, corps, _ = appel("POST", "/v1/auth/connexion", {"email": email, "mot_de_passe": MDP})
    return email, (corps.get("jetons", corps) or {}).get("access_token")


async def main():
    await open_pool()
    try:
        _, jeton_simple = await compte(admin=False)
        email_admin, jeton_admin = await compte(admin=True)

        print("\n· Ce que l'administration refuse")
        for chemin in ("/v1/admin/tableau-de-bord", "/v1/admin/paiements",
                       "/v1/admin/utilisateurs", "/v1/admin/courriels",
                       "/v1/admin/webhooks-orphelins", "/v1/admin/reglages"):
            code, _, _ = appel("GET", chemin)
            ok(f"{chemin} sans jeton", code == 401, code)
        code, corps, _ = appel("GET", "/v1/admin/tableau-de-bord", jeton=jeton_simple)
        ok("un compte ordinaire reçoit 403", code == 403, code)
        # Le message ne doit pas confirmer qu'un espace d'administration existe.
        message = (corps.get("detail") or {}).get("message", "") if isinstance(corps, dict) else ""
        ok("et le refus ne renseigne pas", "admin" not in message.lower(), message)

        print("\n· Les chiffres du tableau de bord")
        code, tb, _ = appel("GET", "/v1/admin/tableau-de-bord?jours=30", jeton=jeton_admin)
        ok("le tableau se charge", code == 200, code)
        ok("il tient en un seul appel",
           set(tb) >= {"comptes", "actifs", "paiements", "abonnements", "courriels",
                       "corpus", "courbe", "exploitation", "activite", "ouvrages",
                       "axes_choisis", "entonnoir", "plans"}, list(tb))

        somme = sum(p["comptes"] for p in tb["courbe"])
        ok("la courbe s'accorde au compteur de la période",
           somme == tb["comptes"]["periode"], f"{somme} contre {tb['comptes']['periode']}")
        ok("elle porte un point par jour, les jours vides compris",
           len(tb["courbe"]) == 30, len(tb["courbe"]))
        ok("chaque point porte ses quatre séries",
           all({"comptes", "paiements", "encaisse", "actifs"} <= set(j) for j in tb["courbe"]),
           tb["courbe"][0])
        # Même contrôle que pour la courbe des comptes
        somme_xaf = sum(j["encaisse"] for j in tb["courbe"])
        ok("l'encaissement de la courbe s'accorde à celui de la période",
           somme_xaf == tb["paiements"]["encaisse_periode"],
           f"{somme_xaf} contre {tb['paiements']['encaisse_periode']}")

        print("\n· Ce que la vue d'ensemble raconte")
        ok("la comparaison avec la période précédente est là",
           "precedent" in tb["comptes"] and "encaisse_precedent" in tb["paiements"])
        ok("l'activité est ventilée par type",
           all({"type", "n", "personnes"} <= set(a) for a in tb["activite"]), tb["activite"][:1])
        ok("et ne compte pas plus de personnes que de gestes",
           all(a["personnes"] <= a["n"] for a in tb["activite"]))
        ok("l'entonnoir porte ses cinq marches",
           {"comptes", "diagnostiques", "plans", "en_marche", "abonnes"} <= set(tb["entonnoir"]),
           list(tb["entonnoir"]))
        # Chaque marche est un sous-ensemble de la précédente.
        e = tb["entonnoir"]
        ok("chaque marche tient dans la précédente",
           e["comptes"] >= e["diagnostiques"] >= e["plans"] >= e["en_marche"],
           e)
        ok("le classement des ouvrages est borné et ordonné",
           len(tb["ouvrages"]) <= 8
           and all(tb["ouvrages"][i]["seances"] >= tb["ouvrages"][i + 1]["seances"]
                   for i in range(len(tb["ouvrages"]) - 1)),
           [o["seances"] for o in tb["ouvrages"]])
        ok("celui des pôles aussi",
           len(tb["axes_choisis"]) <= 8
           and all(tb["axes_choisis"][i]["choix"] >= tb["axes_choisis"][i + 1]["choix"]
                   for i in range(len(tb["axes_choisis"]) - 1)),
           [a["choix"] for a in tb["axes_choisis"]])
        ok("la répartition des formules couvre tous les comptes",
           sum(f["n"] for f in tb["plans"]) == tb["comptes"]["total"],
           tb["plans"])

        vrai = await fetch_one("select count(*) as n from app_user")
        ok("le nombre de comptes est celui de la base",
           tb["comptes"]["total"] == vrai["n"], f"{tb['comptes']['total']} contre {vrai['n']}")

        encaisse = await fetch_one(
            "select coalesce(sum(montant),0) as n from payment where statut = 'valide'")
        ok("l'encaissé ne compte que les paiements validés",
           tb["paiements"]["encaisse"] == encaisse["n"],
           f"{tb['paiements']['encaisse']} contre {encaisse['n']}")

        print("\n· Les listes")
        code, env, _ = appel("GET", "/v1/admin/paiements?statut=valide&par_page=5", jeton=jeton_admin)
        liste = env["lignes"]
        ok("les paiements se filtrent par statut",
           code == 200 and all(p["statut"] == "valide" for p in liste), code)
        ok("chaque ligne porte le compte concerné",
           not liste or all(p.get("email") for p in liste))

        print("\n· Les listes sont paginées")
        for chemin in ("utilisateurs", "paiements", "courriels", "abonnements",
                       "webhooks-orphelins", "corpus"):
            code, e, _ = appel("GET", f"/v1/admin/{chemin}?par_page=5", jeton=jeton_admin)
            forme = code == 200 and {"total", "page", "pages", "lignes"} <= set(e)
            ok(f"{chemin} renvoie une enveloppe paginée",
               forme and len(e["lignes"]) <= 5, code if not forme else len(e["lignes"]))

        code, p1, _ = appel("GET", "/v1/admin/utilisateurs?par_page=3&page=1", jeton=jeton_admin)
        code, p2, _ = appel("GET", "/v1/admin/utilisateurs?par_page=3&page=2", jeton=jeton_admin)
        ok("deux pages successives ne se recouvrent pas",
           not ({l["id"] for l in p1["lignes"]} & {l["id"] for l in p2["lignes"]}))
        ok("le total ne dépend pas de la page", p1["total"] == p2["total"], f"{p1['total']} {p2['total']}")

        code, orph, _ = appel("GET", "/v1/admin/webhooks-orphelins", jeton=jeton_admin)
        ok("les webhooks orphelins se listent", code == 200 and "lignes" in orph, code)

        code, gens, _ = appel("GET", "/v1/admin/utilisateurs?par_page=5", jeton=jeton_admin)
        ok("les comptes se listent", code == 200 and "lignes" in gens, code)
        ok("sans jamais exposer une empreinte de mot de passe",
           not gens["lignes"] or all("password" not in str(k).lower() for k in gens["lignes"][0]),
           list(gens["lignes"][0]) if gens["lignes"] else "")

        print("\n· Les interrupteurs se posent depuis le tableau de bord")
        code, avant, _ = appel("GET", "/v1/admin/reglages", jeton=jeton_admin)
        cles = sorted(r["cle"] for r in avant) if code == 200 else code
        ok("les quatre réglages se lisent", cles == ["lancement", "maintenance", "parrainage", "version_minimale"], cles)

        code, _, _ = appel("POST", "/v1/admin/reglages/lancement",
                           {"valeur": {"actif": False, "jusqu_au": None, "message": "Essai"}},
                           jeton=jeton_admin)
        ok("un réglage se pose", code == 200, code)
        ligne = await fetch_one("select valeur from reglage where cle = 'lancement'")
        ok("et il est bien écrit", ligne["valeur"].get("message") == "Essai", ligne["valeur"])

        code, _, _ = appel("POST", "/v1/admin/reglages/inconnu", {"valeur": {}}, jeton=jeton_admin)
        ok("un réglage inconnu est refusé", code == 404, code)

        code, _, _ = appel("POST", "/v1/admin/reglages/lancement",
                           {"valeur": {"actif": True}}, jeton=jeton_simple)
        ok("un compte ordinaire ne peut rien poser", code == 403, code)

        print("\n· Le contenu du corpus")
        code, envc, _ = appel("GET", "/v1/admin/corpus?par_page=5", jeton=jeton_admin)
        corpus = envc["lignes"]
        ok("le corpus se liste", code == 200 and len(corpus) > 0, code)
        ok("chaque ouvrage porte son état de production",
           not corpus or {"chapitres_utiles", "vectorises", "quiz", "citations", "complet"}
           <= set(corpus[0]), list(corpus[0]) if corpus else "")

        code, inc, _ = appel("GET", "/v1/admin/corpus?manque=true&par_page=40", jeton=jeton_admin)
        ok("le filtre des incomplets ne garde que les incomplets",
           all(not o["complet"] for o in inc["lignes"]), len(inc["lignes"]))
        # Le filtre vit dans le WHERE : sans cela
        ok("et son total est celui des incomplets, pas celui du corpus",
           inc["total"] < envc["total"], f"{inc['total']} sur {envc['total']}")

        un = corpus[0]
        code, detail, _ = appel("GET", f"/v1/admin/corpus/{un['id']}", jeton=jeton_admin)
        ok("un ouvrage s'ouvre en détail",
           code == 200 and {"droits", "axes", "derives", "chapitres"} <= set(detail), code)

        print("\n· Les droits se changent, le reste non")
        avant = detail["droits"]["plafond_extrait"]
        code, _, _ = appel("PATCH", f"/v1/admin/corpus/{un['id']}",
                           {"max_excerpt_chars": 777}, jeton=jeton_admin)
        ok("le plafond de citation se pose", code == 200, code)
        ligne = await fetch_one("select max_excerpt_chars from document where id = %s", (un["id"],))
        ok("et il est écrit en base", ligne["max_excerpt_chars"] == 777, ligne)
        # On rend l'ouvrage tel qu'on l'a trouvé
        await execute("update document set max_excerpt_chars = %s where id = %s",
                      (avant, un["id"]))

        code, _, _ = appel("PATCH", f"/v1/admin/corpus/{un['id']}",
                           {"titre": "Autre chose"}, jeton=jeton_admin)
        ok("le titre ne se change pas depuis la console", code in (404, 422), code)

        code, _, _ = appel("PATCH", f"/v1/admin/corpus/{un['id']}",
                           {"takedown_status": "inventé"}, jeton=jeton_admin)
        ok("un statut de retrait inconnu est refusé", code == 422, code)

        print("\n· Tout se visualise depuis la console")
        code, contenu, _ = appel("GET", f"/v1/admin/corpus/{un['id']}/derives?kind=quiz&par_page=2",
                                 jeton=jeton_admin)
        ok("le contenu produit se lit, pas seulement son compte",
           code == 200 and "lignes" in contenu and
           (not contenu["lignes"] or "contenu" in contenu["lignes"][0]), code)

        code, _, _ = appel("GET", f"/v1/admin/corpus/{un['id']}/derives?kind=nimportequoi",
                           jeton=jeton_admin)
        ok("un type de dérivé inconnu est refusé", code == 422, code)

        print("\n· Les messages se corrigent en base")
        code, gabarits, _ = appel("GET", "/v1/admin/gabarits", jeton=jeton_admin)
        ok("les gabarits se lisent", code == 200 and len(gabarits) >= 5, len(gabarits) if code == 200 else code)
        code, _, _ = appel("PATCH", "/v1/admin/gabarits/bienvenue",
                           {"objet": "Bienvenue sur ASCENDA, {prenom}"}, jeton=jeton_admin)
        ok("un objet se corrige", code == 200, code)
        code, _, _ = appel("PATCH", "/v1/admin/gabarits/inconnu", {"objet": "x"}, jeton=jeton_admin)
        ok("un gabarit inconnu est refusé", code == 404, code)

        print("\n· On ne peut pas se verrouiller dehors")
        mien = await fetch_one("select id from app_user where email = %s", (email_admin,))
        code, _, _ = appel("PATCH", f"/v1/admin/utilisateurs/{mien['id']}",
                           {"est_admin": False}, jeton=jeton_admin)
        ok("retirer son propre droit est refusé", code == 409, code)
        toujours = await fetch_one("select est_admin from app_user where id = %s", (mien["id"],))
        ok("et le droit est resté", toujours["est_admin"] is True, toujours)

        print("\n· La page elle-même")
        code, _, _ = appel("GET", "/admin")
        ok("elle se sert sans jeton, c'est la page de connexion", code == 200, code)
    finally:
        await execute(
            """update reglage set valeur = jsonb_build_object(
                 'actif', false, 'jusqu_au', null,
                 'message', 'Pendant le lancement, tout ASCENDA est ouvert. Profitez-en.')
               where cle = 'lancement'""")
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
