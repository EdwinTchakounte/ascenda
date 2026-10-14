"""Le journal des modifications : ce que les triggers écrivent, et ce qu'ils taisent."""
import asyncio
import os
import sys
import urllib.request
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "apps" / "api"))
sys.path.insert(0, str(RACINE / "tests"))

from commun import appel, suffixe  # noqa: E402

from app.core.db import close_pool, execute, fetch_all, fetch_one, open_pool  # noqa: E402
from app.core.security import hash_password  # noqa: E402

_resultats = []
MDP = "lecture-guidee-2026"
MARQUE = "journal"


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


async def compte(admin=False):
    email = f"{MARQUE}-{suffixe()}@example.com"
    await execute(
        """insert into app_user (email, display_name, password_hash, plan, est_admin)
           values (%s, 'Vérification', %s, 'free', %s)""",
        (email, hash_password(MDP), admin),
    )
    _, r, _ = appel("POST", "/v1/auth/connexion", {"email": email, "mot_de_passe": MDP})
    ligne = await fetch_one("select id from app_user where email = %s", (email,))
    return str(ligne["id"]), email, r["jetons"]["access_token"]


def telecharger(chemin, jeton):
    """Le corps tel quel : `appel` ramène les réponses non JSON à leur taille."""
    requete = urllib.request.Request(os.environ.get("ASCENDA_API", "http://127.0.0.1:8250") + chemin)
    requete.add_header("Authorization", f"Bearer {jeton}")
    with urllib.request.urlopen(requete, timeout=90) as r:
        return r.status, r.read().decode("utf-8"), r.headers.get("Content-Disposition", "")


async def entrees(relation, cle):
    return await fetch_all(
        """select operation, acteur, avant, apres, ecart from journal_modification
            where relation = %s and cle = %s order by id""", (relation, str(cle)))


async def main():
    await open_pool()
    comptes = []
    try:
        print("\n· Le trigger voit les écritures")
        user_id, email, jeton = await compte(admin=True)
        comptes.append(user_id)
        lignes = await entrees("app_user", user_id)
        ok("la création d'un compte laisse une trace", [l for l in lignes if l["operation"] == "insert"],
           [l["operation"] for l in lignes])
        creation = next((l for l in lignes if l["operation"] == "insert"), {})
        ok("l'insertion n'a pas d'état antérieur", creation.get("avant") is None)
        ok("l'insertion garde la ligne créée", (creation.get("apres") or {}).get("email") == email)
        ok("l'empreinte du mot de passe n'est jamais recopiée",
           (creation.get("apres") or {}).get("password_hash") == "(masqué)",
           (creation.get("apres") or {}).get("password_hash"))

        print("\n· L'écart dit ce qui a changé")
        await execute("update app_user set display_name = 'Relu' where id = %s", (user_id,))
        lignes = await entrees("app_user", user_id)
        maj = [l for l in lignes if l["operation"] == "update"]
        ok("la mise à jour laisse une trace", len(maj) == 1, len(maj))
        ecart = (maj[0]["ecart"] if maj else None) or {}
        ok("l'écart nomme la seule colonne touchée", list(ecart) == ["display_name"], list(ecart))
        ok("l'écart porte l'ancienne et la nouvelle valeur",
           ecart.get("display_name") == ["Vérification", "Relu"], ecart.get("display_name"))
        ok("l'état antérieur et l'état suivant sont tous deux gardés",
           (maj[0]["avant"] or {}).get("display_name") == "Vérification"
           and (maj[0]["apres"] or {}).get("display_name") == "Relu" if maj else False)

        print("\n· Ce qui ne mérite pas de trace")
        avant = len(await entrees("app_user", user_id))
        await execute("update app_user set display_name = 'Relu' where id = %s", (user_id,))
        await execute("update app_user set last_login_at = now() where id = %s", (user_id,))
        apres = len(await entrees("app_user", user_id))
        ok("une mise à jour qui ne change rien n'écrit pas", apres == avant, f"{avant} → {apres}")

        print("\n· L'acteur")
        statut_quota, r, _ = appel("PUT", "/v1/admin/quotas/free/agent_tokens/month", {"max_value": 123456},
                        jeton=jeton)
        ligne = await fetch_one(
            """select acteur from journal_modification
                where relation = 'plan_quota' order by id desc limit 1""")
        ok("une écriture par la console porte le courriel de l'administrateur",
           (ligne or {}).get("acteur", "").endswith(email), (ligne or {}).get("acteur"))
        ok("l'administrateur est signalé comme tel",
           (ligne or {}).get("acteur", "").startswith("administrateur"), (ligne or {}).get("acteur"))

        print("\n· La console lit le journal")
        s, j, _ = appel("GET", "/v1/admin/journal?jours=1&relation=app_user", jeton=jeton)
        ok("le journal se lit", s == 200, s)
        ok("il est paginé", {"lignes", "total", "pages", "relations"} <= set(j or {}), list(j or {}))
        ok("les tables surveillées sont annoncées", "app_user" in (j or {}).get("relations", []),
           (j or {}).get("relations"))
        ok("une ligne porte son résumé et ses changements",
           all({"le", "table", "operation", "acteur", "resume", "changements"} <= set(x)
               for x in (j or {}).get("lignes", [])))
        une = next((x for x in (j or {}).get("lignes", []) if x["operation"] == "update"), None)
        ok("un changement se lit champ par champ",
           une and all({"champ", "avant", "apres"} <= set(c) for c in une["changements"]),
           une["changements"] if une else None)

        s, detail, _ = appel("GET", f"/v1/admin/journal/{une['id']}", jeton=jeton) if une else (0, {}, 0)
        ok("l'entrée entière se lit", s == 200 and {"avant", "apres"} <= set(detail or {}), s)

        print("\n· L'export en tableur")
        s, texte, disposition = telecharger("/v1/admin/journal.csv?jours=1&relation=app_user", jeton)
        ok("le fichier se télécharge", s == 200, s)
        ok("il est proposé en pièce jointe, nommé et daté",
           disposition.startswith("attachment") and "ascenda-journal-" in disposition
           and disposition.endswith(".csv"), disposition)
        lignes = [l for l in texte.splitlines() if l.strip()]
        ok("il commence par la marque d'octets et le séparateur",
           texte.startswith("\ufeffsep=;"), texte[:12].encode("unicode_escape").decode())
        ok("l'en-tête nomme les colonnes",
           lignes[1].split(";") == ["entrée", "quand", "table", "geste", "ligne", "qui",
                                    "colonne", "avant", "après"],
           lignes[1])
        ok("il porte autant de lignes que de changements", len(lignes) > 2, len(lignes))
        ok("une modification se lit colonne par colonne",
           any(l.split(";")[6] == "display_name" and l.split(";")[8] == "Relu" for l in lignes[2:]),
           [l for l in lignes[2:4]])
        ok("une création n'invente pas de colonne changée",
           any(l.split(";")[3] == "création" and l.split(";")[6] == "" for l in lignes[2:]))

        print("\n· Le journal n'est pas public")
        lecteur_id, _, lecteur = await compte(admin=False)
        comptes.append(lecteur_id)
        s, _, _ = appel("GET", "/v1/admin/journal", jeton=lecteur)
        ok("un lecteur ne voit pas le journal", s == 403, s)
        s, _, _ = appel("GET", "/v1/admin/journal.csv", jeton=lecteur)
        ok("ni le fichier", s == 403, s)
        s, _, _ = appel("GET", "/v1/admin/journal")
        ok("sans jeton non plus", s in (401, 403), s)

        print("\n· La suppression")
        pour_effacer, _, _ = await compte()
        await execute("delete from app_user where id = %s", (pour_effacer,))
        lignes = await entrees("app_user", pour_effacer)
        suppression = next((l for l in lignes if l["operation"] == "delete"), None)
        ok("la suppression garde la ligne disparue",
           suppression and suppression["apres"] is None and suppression["avant"] is not None)
    finally:
        for c in comptes:
            await execute("delete from app_user where id = %s", (c,))
        await execute("update plan_quota set max_value = 600000 "
                      "where plan = 'free' and type = 'agent_tokens'")
        await execute("delete from journal_modification where acteur like %s or avant::text like %s "
                      "or apres::text like %s",
                      (f"%{MARQUE}-%", f"%{MARQUE}-%", f"%{MARQUE}-%"))
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
