"""La réinitialisation de mot de passe, et ce qu'elle refuse."""
import asyncio
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "apps" / "api"))

from app.core.db import close_pool, execute, fetch_all, fetch_one, open_pool  # noqa: E402
from app.core.security import hash_password, verify_password  # noqa: E402
from app.services import mot_de_passe  # noqa: E402

_resultats = []


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


async def compte(suffixe: str, motdepasse: str = "AncienMotDePasse1!"):
    return await fetch_one(
        """insert into app_user (email, display_name, password_hash, plan)
           values (%s, 'Essai', %s, 'free') returning *""",
        (f"mdp-{suffixe}-{uuid.uuid4().hex[:6]}@example.com", hash_password(motdepasse)),
    )


async def empreinte(user_id):
    return (await fetch_one("select password_hash from app_user where id = %s", (user_id,)))[
        "password_hash"
    ]


async def main():
    await open_pool()

    print("\n· Le code lui-même")
    codes = {mot_de_passe.nouveau_code() for _ in range(200)}
    ok("six chiffres", all(len(c) == 6 and c.isdigit() for c in codes))
    ok("deux cents tirages donnent deux cents codes distincts", len(codes) > 190, len(codes))

    print("\n· Le parcours nominal")
    u = await compte("nominal")
    resultat = await mot_de_passe.demander(u["email"])
    ok("une adresse connue produit un code", resultat is not None)
    _, code = resultat
    ancienne = await empreinte(u["id"])
    rendu = await mot_de_passe.reinitialiser(u["email"], code, "NouveauMotDePasse1!")
    ok("le bon code réinitialise", rendu is not None)
    nouvelle = await empreinte(u["id"])
    ok("l'empreinte a changé", ancienne != nouvelle)
    ok("le nouveau mot de passe ouvre le compte",
       verify_password("NouveauMotDePasse1!", nouvelle))
    ok("l'ancien ne l'ouvre plus", not verify_password("AncienMotDePasse1!", nouvelle))

    print("\n· Le code recopié avec des espaces reste valable")
    u = await compte("espaces")
    _, code = await mot_de_passe.demander(u["email"])
    espace = f"{code[:3]} {code[3:]}"
    ok("« 123 456 » vaut « 123456 »",
       await mot_de_passe.reinitialiser(u["email"], espace, "NouveauMotDePasse1!") is not None,
       espace)

    print("\n· Ce que la réinitialisation referme derrière elle")
    u = await compte("sessions")
    await execute(
        """insert into refresh_token (user_id, token_hash, expires_at)
           values (%s, %s, now() + interval '60 days')""",
        # Une empreinte unique : la colonne l'exige, et une suite doit pouvoir
        # se rejouer sans qu'on nettoie la base entre deux passages.
        (u["id"], f"essai-{uuid.uuid4().hex}"),
    )
    _, code = await mot_de_passe.demander(u["email"])
    await mot_de_passe.reinitialiser(u["email"], code, "NouveauMotDePasse1!")
    vivants = await fetch_all(
        "select 1 from refresh_token where user_id = %s and revoked_at is null", (u["id"],)
    )
    ok("toutes les sessions sont révoquées", not vivants, f"{len(vivants)} encore vivante(s)")

    print("\n· Un code ne sert qu'une fois")
    u = await compte("unique")
    _, code = await mot_de_passe.demander(u["email"])
    await mot_de_passe.reinitialiser(u["email"], code, "Premier1MotDePasse!")
    second = await mot_de_passe.reinitialiser(u["email"], code, "Second1MotDePasse!")
    ok("le rejeu est refusé", second is None)
    ok("le premier mot de passe tient toujours",
       verify_password("Premier1MotDePasse!", await empreinte(u["id"])))

    print("\n· Le compteur d'essais")
    u = await compte("essais")
    _, code = await mot_de_passe.demander(u["email"])
    faux = "000000" if code != "000000" else "111111"
    for i in range(mot_de_passe.TENTATIVES_MAX):
        await mot_de_passe.reinitialiser(u["email"], faux, "Peu1Importe!")
    apres = await mot_de_passe.reinitialiser(u["email"], code, "Peu1Importe!")
    ok(f"après {mot_de_passe.TENTATIVES_MAX} essais, le bon code ne passe plus", apres is None)
    ok("le mot de passe n'a pas bougé",
       verify_password("AncienMotDePasse1!", await empreinte(u["id"])))

    print("\n· L'expiration")
    u = await compte("expire")
    _, code = await mot_de_passe.demander(u["email"])
    await execute(
        """update password_reset set expires_at = now() - interval '1 minute'
            where user_id = %s""",
        (u["id"],),
    )
    ok("un code expiré est refusé",
       await mot_de_passe.reinitialiser(u["email"], code, "Peu1Importe!") is None)

    print("\n· La cadence des demandes")
    u = await compte("cadence")
    premiere = await mot_de_passe.demander(u["email"])
    seconde = await mot_de_passe.demander(u["email"])
    ok("la première demande passe", premiere is not None)
    ok("la seconde, immédiate, est refusée", seconde is None)
    lignes = await fetch_all("select 1 from password_reset where user_id = %s", (u["id"],))
    ok("un seul code a été créé", len(lignes) == 1, f"{len(lignes)}")

    print("\n· Ce que le service ne révèle pas")
    ok("une adresse inconnue ne produit rien",
       await mot_de_passe.demander(f"inexistant-{uuid.uuid4().hex}@example.com") is None)
    u = await compte("desactive")
    await execute("update app_user set is_active = false where id = %s", (u["id"],))
    ok("un compte désactivé ne produit rien", await mot_de_passe.demander(u["email"]) is None)

    print("\n· Un second code annule le premier")
    u = await compte("deuxcodes")
    _, code1 = await mot_de_passe.demander(u["email"])
    # On recule la première demande pour sortir du délai de cadence.
    await execute(
        """update password_reset set created_at = now() - interval '20 minutes'
            where user_id = %s""",
        (u["id"],),
    )
    _, code2 = await mot_de_passe.demander(u["email"])
    ok("le second code fonctionne",
       await mot_de_passe.reinitialiser(u["email"], code2, "Nouveau1MotDePasse!") is not None)
    ok("le premier est devenu inutilisable",
       await mot_de_passe.reinitialiser(u["email"], code1, "Autre1MotDePasse!") is None)

    print("\n· Le code n'est jamais stocké en clair")
    u = await compte("clair")
    _, code = await mot_de_passe.demander(u["email"])
    ligne = await fetch_one(
        "select code_hash from password_reset where user_id = %s", (u["id"],)
    )
    ok("la base ne contient que l'empreinte", ligne["code_hash"] != code,
       ligne["code_hash"][:16] + "...")
    ok("l'empreinte fait bien 64 caractères", len(ligne["code_hash"]) == 64)

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
