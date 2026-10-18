"""Le module d'extension : déposer un ouvrage, étendre les pôles, suivre les travaux."""
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
from app.services import travaux  # noqa: E402

_resultats = []
MDP = "MotDePasse123!"


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


async def admin():
    email = f"imp-{suffixe()}-{uuid.uuid4().hex[:4]}@example.com"
    await execute(
        """insert into app_user (email, display_name, password_hash, plan, est_admin)
           values (%s, 'Essai', %s, 'free', true)""",
        (email, hash_password(MDP)),
    )
    _, corps, _ = appel("POST", "/v1/auth/connexion", {"email": email, "mot_de_passe": MDP})
    return email, (corps.get("jetons", corps) or {}).get("access_token")


async def main():
    await open_pool()
    crees = []
    try:
        email, jeton = await admin()

        print("\n· La file des travaux")
        code, env, _ = appel("GET", "/v1/admin/travaux?par_page=5", jeton=jeton)
        ok("la file se lit", code == 200 and {"total", "lignes"} <= set(env), code)

        t = await travaux.inscrire("import_data", {"essai": True})
        crees.append(str(t["id"]))
        ok("un travail s'inscrit", not t.get("deja") and t["etat"] == "en_attente", t.get("etat"))

        # Deux vectorisations en parallèle se disputeraient le processeur pour faire deux
        # fois
        double = await travaux.inscrire("import_data", {})
        ok("le même travail lourd ne s'inscrit pas deux fois", double.get("deja") is True)

        ok("un type inconnu est refusé",
           await _leve(travaux.inscrire, "n-importe-quoi"))

        print("\n· Ce qu'on peut faire d'un travail")
        vu = await travaux.un(str(t["id"]))
        ok("il se relit avec son libellé", vu and vu["libelle"], (vu or {}).get("libelle"))
        ok("et sa durée attendue", (vu or {}).get("duree_attendue_min"), (vu or {}).get("duree_attendue_min"))
        ok("un travail en attente s'annule", await travaux.annuler(str(t["id"])) is True)
        ok("mais pas deux fois", await travaux.annuler(str(t["id"])) is False)
        ok("un travail annulé se relance", await travaux.relancer(str(t["id"])) is not None)

        print("\n· Le dépôt d'un fichier")
        code, corps, _ = appel("POST", "/v1/admin/travaux",
                               {"type": "vecteurs"}, jeton=jeton)
        if code == 201:
            crees.append(corps["id"])
        ok("une étape se lance depuis la console", code in (201, 409), code)

        code, _, _ = appel("POST", "/v1/admin/travaux", {"type": "inventé"}, jeton=jeton)
        ok("un type de travail inconnu est refusé par la route", code == 422, code)

        print("\n· Les pôles d'apprentissage")
        code, axes, _ = appel("GET", "/v1/admin/axes", jeton=jeton)
        ok("les axes se listent avec leur nombre d'ouvrages",
           code == 200 and axes and "ouvrages" in axes[0], code)

        slug = f"99-essai-{suffixe(4)}"
        code, cree, _ = appel("POST", "/v1/admin/axes",
                              {"slug": slug, "label": "Essai"}, jeton=jeton)
        ok("un axe se crée", code == 201, code)
        code, _, _ = appel("POST", "/v1/admin/axes",
                           {"slug": slug, "label": "Autre"}, jeton=jeton)
        ok("un raccourci déjà pris est refusé", code == 409, code)
        code, _, _ = appel("POST", "/v1/admin/axes",
                           {"slug": "Avec Majuscules", "label": "Non"}, jeton=jeton)
        ok("un raccourci mal formé est refusé", code == 422, code)

        code, _, _ = appel("PATCH", f"/v1/admin/axes/{slug}",
                           {"label": "Essai renommé"}, jeton=jeton)
        ok("un axe se renomme", code == 200, code)
        ligne = await fetch_one("select label from axis where slug = %s", (slug,))
        ok("et le nom est écrit", ligne["label"] == "Essai renommé", ligne)

        print("\n· Rattacher un ouvrage à un pôle")
        doc = await fetch_one("select id from document where takedown_status = 'none' limit 1")
        code, _, _ = appel("POST", f"/v1/admin/corpus/{doc['id']}/axes/{slug}?poids=0.5",
                           jeton=jeton)
        ok("un ouvrage se rattache", code == 200, code)
        lien = await fetch_one(
            """select weight, assigned_by from document_axis da join axis a on a.id = da.axis_id
                where da.document_id = %s and a.slug = %s""", (doc["id"], slug))
        ok("le poids et la provenance sont notés",
           lien and float(lien["weight"]) == 0.5 and lien["assigned_by"] == "curator", lien)

        code, _, _ = appel("POST", f"/v1/admin/corpus/{doc['id']}/axes/{slug}?poids=0.9",
                           jeton=jeton)
        ok("le rattacher deux fois met à jour au lieu d'échouer", code == 200, code)

        code, _, _ = appel("DELETE", f"/v1/admin/corpus/{doc['id']}/axes/{slug}", jeton=jeton)
        ok("il se détache", code == 204, code)

        code, _, _ = appel("POST", f"/v1/admin/corpus/{doc['id']}/axes/n-existe-pas", jeton=jeton)
        ok("un axe inconnu est refusé", code == 404, code)

        await execute("delete from axis where slug = %s", (slug,))

        print("\n· La zone de dépôt reste hors de la vue du lecteur")
        await execute(
            """insert into axis (slug, label) values ('_essai-depot', 'Dépôt d''essai')
               on conflict (slug) do nothing""")
        code, publics, _ = appel("GET", "/v1/axes")
        ok("les zones de dépôt ne sont pas listées",
           code == 200 and not [a for a in publics if a["slug"].startswith("_")],
           [a["slug"] for a in publics if a["slug"].startswith("_")])
        code, _, _ = appel("GET", "/v1/axes/_essai-depot")
        ok("et leur fiche n'existe pas", code == 404, code)
        code, filtres, _ = appel("GET", "/v1/bibliotheque/filtres")
        ok("elles ne sont pas proposées en filtre",
           code == 200 and not [a for a in filtres["axes"] if a["valeur"].startswith("_")])
        code, _, _ = appel("POST", "/v1/chronogrammes",
                           {"axe": "_essai-depot", "minutes_par_jour": 30, "jours": 7},
                           jeton=jeton)
        ok("et on ne peut pas s'y bâtir un parcours", code in (404, 422), code)
        await execute("delete from axis where slug = '_essai-depot'")

        code, axes_console, _ = appel("GET", "/v1/admin/axes", jeton=jeton)
        ok("la console, elle, voit tout", code == 200 and len(axes_console) >= 11, code)

        print("\n· L'ouvrier sait quoi lancer")
        sys.path.insert(0, str(RACINE / "pipeline"))
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "travailleur", RACINE / "pipeline" / "travailleur.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        ok("les types de l'API et ceux de l'ouvrier concordent",
           set(travaux.RECETTES) == set(module.COMMANDES),
           set(travaux.RECETTES) ^ set(module.COMMANDES))
    finally:
        for i in crees:
            await execute("delete from travail where id = %s", (i,))
        await close_pool()


async def _leve(fonction, *a):
    try:
        await fonction(*a)
        return False
    except ValueError:
        return True


asyncio.run(main())

print("\n" + "=" * 92)
_echecs = [x for x in _resultats if not x[0]]
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
