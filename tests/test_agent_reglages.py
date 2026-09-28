"""Le réglage de l'agent depuis la console, et les plafonds de jetons.

Ce qui doit tenir :

- une clé posée depuis la console est chiffrée en base, jamais relue en clair,
  et la console n'en voit que les quatre derniers caractères ;
- activer un fournisseur sans clé est refusé ;
- retirer la clé coupe le fournisseur ;
- le modèle et le plafond de réponse se changent sans redéploiement ;
- un plafond de jetons se change depuis la console et s'applique ;
- un plafond de jetons dépassé bloque la question suivante, avant l'appel au
  modèle et non après ;
- un code d'accès peut porter son propre plafond, compté depuis l'activation,
  et c'est le plus serré des deux qui s'applique ;
- la console sait ce que l'agent a coûté.

Les appels passent par HTTP comme ceux de l'application. La consommation est
écrite directement en base : poser deux cents questions au modèle n'est pas un
test, c'est une facture.
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
from app.services import fournisseurs  # noqa: E402

_resultats = []
MDP = "lecture-guidee-2026"
MARQUE = "agentreg"


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
    return str(ligne["id"]), r["jetons"]["access_token"]


async def consommer(user_id: str, jetons: int):
    """Écrit une consommation comme le ferait une question réellement posée."""
    await execute(
        """insert into usage_event (user_id, type, quantity, cost_tokens)
           values (%s, 'agent_tokens', 1, %s)""",
        (user_id, jetons),
    )


async def main():
    await open_pool()
    etat_initial = await fetch_one(
        "select modele, actif, max_tokens_reponse, cle_chiffree, cle_indice "
        "from fournisseur_ia where code = 'openai'"
    )
    plafond_initial = await fetch_one(
        "select max_value, hard from plan_quota where plan = 'free' and type = 'agent_tokens'"
    )
    try:
        _, jeton_admin = await compte(admin=True)

        # ---- le fournisseur, sa clé, son modèle
        st, vue, _ = appel("GET", "/v1/admin/agent", jeton=jeton_admin)
        codes = [f["code"] for f in (vue or {}).get("fournisseurs", [])]
        ok("la console liste les deux fournisseurs", st == 200 and codes == ["anthropic", "openai"], codes)

        st, r, _ = appel("PUT", "/v1/admin/agent/openai", {"actif": True}, jeton=jeton_admin)
        ok("activer sans clé est refusé", st == 409, r)

        cle = "sk-verification-" + uuid.uuid4().hex
        st, r, _ = appel("PUT", "/v1/admin/agent/openai",
                         {"cle": cle, "modele": "gpt-5", "actif": True, "max_tokens_reponse": 900},
                         jeton=jeton_admin)
        ok("la clé se pose depuis la console", st == 200 and r["cle_posee"] and r["actif"], r)
        ok("et la console n'en voit que la fin", (r or {}).get("cle_indice") == cle[-4:], r.get("cle_indice"))
        ok("la réponse ne contient jamais la clé", cle not in str(r))

        ligne = await fetch_one("select cle_chiffree from fournisseur_ia where code = 'openai'")
        brut = bytes(ligne["cle_chiffree"])
        ok("la clé est chiffrée en base", cle.encode() not in brut and len(brut) > 12, len(brut))
        ok("et se relit avec le secret de l'installation", fournisseurs.dechiffrer(brut) == cle)

        st, vue, _ = appel("GET", "/v1/admin/agent", jeton=jeton_admin)
        openai = next(f for f in vue["fournisseurs"] if f["code"] == "openai")
        ok("le modèle retenu est celui posé", openai["modele"] == "gpt-5", openai["modele"])
        ok("le fournisseur est prêt à répondre", "openai" in vue["prets"], vue["prets"])

        st, _, _ = appel("DELETE", "/v1/admin/agent/openai/cle", jeton=jeton_admin)
        st2, vue, _ = appel("GET", "/v1/admin/agent", jeton=jeton_admin)
        openai = next(f for f in vue["fournisseurs"] if f["code"] == "openai")
        ok("retirer la clé coupe le fournisseur",
           st == 204 and not openai["cle_posee"] and not openai["actif"], openai)

        # ---- les plafonds de jetons
        st, r, _ = appel("PUT", "/v1/admin/quotas/free/agent_tokens/month",
                         {"max_value": 5000, "hard": True}, jeton=jeton_admin)
        ok("un plafond de jetons se change depuis la console", st == 200, r)

        user_id, jeton = await compte()
        _, usage, _ = appel("GET", "/v1/compte/usage", jeton=jeton)
        compteur = next((c for c in usage["compteurs"] if c["type"] == "agent_tokens"), None)
        ok("le lecteur voit son volume", compteur and compteur["limite"] == 5000, compteur)

        await consommer(user_id, 4800)
        st, r, _ = appel("POST", "/v1/agent/questions",
                         {"question": "Que dit le corpus sur la fertilité des sols ?"}, jeton=jeton)
        ok("le plafond de jetons bloque la question suivante", st == 402, (st, r))
        ok("et le message dit quoi faire", "recharge" in str(r).lower() or "Ascension" in str(r), r)

        # ---- le plafond porté par un code d'accès
        st, code, _ = appel("POST", "/v1/admin/codes", {
            "code": f"JETONS-{suffixe(4).upper()}", "libelle": "Plafond de jetons",
            "niveau": "complet", "fin": "2027-01-01T00:00:00+00:00", "plafond_tokens": 3000,
        }, jeton=jeton_admin)
        ok("un code peut porter son plafond de jetons",
           st == 201 and code["plafond_tokens"] == 3000, (st, code))

        user2, jeton2 = await compte()
        st, r, _ = appel("POST", "/v1/codes/activer", {"code": code["code"]}, jeton=jeton2)
        ok("le code s'active", st in (200, 201), (st, r))

        _, usage, _ = appel("GET", "/v1/compte/usage", jeton=jeton2)
        compteur = next((c for c in usage["compteurs"] if c["type"] == "agent_tokens"), None)
        ok("le plafond du code l'emporte sur celui de la formule ouverte",
           compteur and compteur["limite"] == 3000, compteur)

        await consommer(user2, 2900)
        st, r, _ = appel("POST", "/v1/agent/questions",
                         {"question": "Que dit le corpus sur la rotation des cultures ?"}, jeton=jeton2)
        ok("et il bloque quand il est atteint", st == 402, (st, r))
        ok("et le message nomme le code, qui ne se recharge pas",
           code["code"] in str(r) and "mois" not in str(r), r)

        # ---- la consommation vue de la console
        st, conso, _ = appel("GET", "/v1/admin/agent/consommation?jours=1", jeton=jeton_admin)
        ok("la console sait ce que l'agent a coûté",
           st == 200 and conso["jetons"] >= 7700, (st, conso.get("jetons")))
    finally:
        await execute("delete from app_user where email like %s", (f"{MARQUE}-%@example.com",))
        await execute("delete from code_acces where code like 'JETONS-%%'")
        await execute(
            """update fournisseur_ia set modele = %s, actif = %s, max_tokens_reponse = %s,
                      cle_chiffree = %s, cle_indice = %s where code = 'openai'""",
            (etat_initial["modele"], etat_initial["actif"], etat_initial["max_tokens_reponse"],
             etat_initial["cle_chiffree"], etat_initial["cle_indice"]),
        )
        await execute(
            "update plan_quota set max_value = %s, hard = %s "
            "where plan = 'free' and type = 'agent_tokens'",
            (plafond_initial["max_value"], plafond_initial["hard"]),
        )
        fournisseurs.oublier()
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
