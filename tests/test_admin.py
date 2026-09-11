"""Le tableau de bord d'exploitation, et surtout ce qu'il refuse.

Un espace d'administration donne accès aux comptes et aux paiements de tout le
monde. Ce qui est vérifié ici tient en deux moitiés : les chiffres qu'il
affiche sont justes, et personne n'y entre sans le droit.
"""
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
        _, jeton_admin = await compte(admin=True)

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
                       "corpus", "courbe", "exploitation"}, list(tb))

        # La somme de la courbe doit égaler le compteur de la période. C'est ce
        # qui manquait : une double jointure multipliait les comptes par le
        # nombre de paiements du jour, et la courbe annonçait cent six mille
        # inscriptions pour sept cent quatre-vingt-neuf comptes.
        somme = sum(p["comptes"] for p in tb["courbe"])
        ok("la courbe s'accorde au compteur de la période",
           somme == tb["comptes"]["periode"], f"{somme} contre {tb['comptes']['periode']}")
        ok("elle porte un point par jour, les jours vides compris",
           len(tb["courbe"]) == 30, len(tb["courbe"]))

        vrai = await fetch_one("select count(*) as n from app_user")
        ok("le nombre de comptes est celui de la base",
           tb["comptes"]["total"] == vrai["n"], f"{tb['comptes']['total']} contre {vrai['n']}")

        encaisse = await fetch_one(
            "select coalesce(sum(montant),0) as n from payment where statut = 'valide'")
        ok("l'encaissé ne compte que les paiements validés",
           tb["paiements"]["encaisse"] == encaisse["n"],
           f"{tb['paiements']['encaisse']} contre {encaisse['n']}")

        print("\n· Les listes")
        code, liste, _ = appel("GET", "/v1/admin/paiements?statut=valide&limite=5", jeton=jeton_admin)
        ok("les paiements se filtrent par statut",
           code == 200 and all(p["statut"] == "valide" for p in liste), code)
        ok("chaque ligne porte le compte concerné",
           not liste or all(p.get("email") for p in liste))

        code, orph, _ = appel("GET", "/v1/admin/webhooks-orphelins", jeton=jeton_admin)
        ok("les webhooks orphelins se listent", code == 200 and isinstance(orph, list), code)

        code, gens, _ = appel("GET", "/v1/admin/utilisateurs?limite=5", jeton=jeton_admin)
        ok("les comptes se listent", code == 200 and isinstance(gens, list), code)
        ok("sans jamais exposer une empreinte de mot de passe",
           not gens or all("password" not in str(k).lower() for k in gens[0]), list(gens[0]) if gens else "")

        print("\n· Les interrupteurs se posent depuis le tableau de bord")
        code, avant, _ = appel("GET", "/v1/admin/reglages", jeton=jeton_admin)
        ok("les trois réglages se lisent", code == 200 and len(avant) == 3, len(avant) if code == 200 else code)

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
