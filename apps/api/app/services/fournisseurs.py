"""Les fournisseurs de modèle : leur réglage, leur clé, leur ordre d'appel.

Le principe : ce qui doit pouvoir changer un dimanche soir ne vit pas dans une
image Docker. Le modèle, la clé et l'ordre d'appel sont en base, posés depuis la
console, et l'API les relit sans redémarrer.

La clé est chiffrée en AES-256-GCM. La clé de chiffrement n'est pas stockée :
elle est dérivée de `JWT_SECRET` par HKDF, donc une copie de la base sans le
fichier d'environnement ne donne rien. En sens inverse, changer `JWT_SECRET`
rend les clés illisibles : c'est voulu, et la console le dit alors clairement au
lieu d'appeler un fournisseur avec une clé fausse.

Rien ici ne renvoie jamais une clé en clair vers le client. La console en voit
la présence et les quatre derniers caractères, ce qui suffit à savoir laquelle
est posée.
"""
import logging
import os
import time

from app.core.config import settings
from app.core.db import execute, fetch_all, fetch_one

log = logging.getLogger("ascenda.fournisseurs")

CODES = ("anthropic", "openai")

# Un cache très court : la configuration est lue à chaque question, et une
# question par seconde ne doit pas valoir une requête de plus. Trente secondes
# suffisent à ce qu'un changement posé depuis la console se voie tout de suite.
_DUREE_CACHE = 30.0
_cache: tuple[float, list[dict]] | None = None


def oublier() -> None:
    """À appeler après toute écriture : la prochaine lecture ira en base."""
    global _cache
    _cache = None


def _clef() -> bytes:
    """La clé de chiffrement, dérivée du secret de l'installation."""
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF

    return HKDF(
        algorithm=hashes.SHA256(), length=32, salt=None,
        info=b"ascenda.fournisseur_ia.v1",
    ).derive(settings.jwt_secret.encode())


def chiffrer(cle: str) -> bytes:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    nonce = os.urandom(12)
    return nonce + AESGCM(_clef()).encrypt(nonce, cle.encode(), None)


def dechiffrer(scelle: bytes | memoryview | None) -> str | None:
    if not scelle:
        return None
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    brut = bytes(scelle)
    try:
        return AESGCM(_clef()).decrypt(brut[:12], brut[12:], None).decode()
    except Exception:  # noqa: BLE001
        # Secret changé, ou base restaurée ailleurs. On ne devine pas : on le dit.
        log.error("Clé d'un fournisseur illisible : JWT_SECRET a-t-il changé ?")
        return None


async def tous() -> list[dict]:
    """Les deux fournisseurs, tels que la console doit les montrer."""
    return await fetch_all(
        """select code, libelle, modele, actif, ordre, max_tokens_reponse,
                  cle_indice, cle_chiffree is not null as cle_posee, updated_at
             from fournisseur_ia order by ordre, code"""
    )


async def actifs() -> list[dict]:
    """Ceux qu'on peut réellement appeler, dans l'ordre, clé déchiffrée.

    Sans aucun fournisseur actif en base, on retombe sur la clé du fichier
    d'environnement : une installation qui n'a jamais ouvert la console continue
    de fonctionner exactement comme avant.
    """
    global _cache
    if _cache and time.monotonic() - _cache[0] < _DUREE_CACHE:
        return _cache[1]

    lignes = await fetch_all(
        """select code, modele, cle_chiffree, max_tokens_reponse
             from fournisseur_ia where actif and cle_chiffree is not null
            order by ordre, code"""
    )
    prets = []
    for l in lignes:
        cle = dechiffrer(l["cle_chiffree"])
        if not cle:
            continue
        prets.append({
            "code": l["code"], "modele": l["modele"], "cle": cle,
            "max_tokens": int(l["max_tokens_reponse"]),
        })
    if not prets and settings.anthropic_api_key:
        prets = [{
            "code": "anthropic", "modele": settings.agent_model,
            "cle": settings.anthropic_api_key, "max_tokens": 1400,
        }]
    _cache = (time.monotonic(), prets)
    return prets


async def enregistrer(code: str, champs: dict, par: str | None = None) -> dict:
    """Écrit un réglage. `cle` est chiffrée ici, et n'est jamais relue ensuite."""
    if code not in CODES:
        raise ValueError("Fournisseur inconnu.")
    colonnes, valeurs = [], []
    for nom in ("modele", "actif", "ordre", "max_tokens_reponse"):
        if champs.get(nom) is not None:
            colonnes.append(f"{nom} = %s")
            valeurs.append(champs[nom])
    cle = (champs.get("cle") or "").strip()
    if cle:
        colonnes += ["cle_chiffree = %s", "cle_indice = %s"]
        valeurs += [chiffrer(cle), cle[-4:]]
    colonnes += ["updated_at = now()", "updated_by = %s"]
    valeurs.append(par)
    await execute(
        f"update fournisseur_ia set {', '.join(colonnes)} where code = %s", valeurs + [code]
    )
    oublier()
    return await fetch_one(
        """select code, libelle, modele, actif, ordre, max_tokens_reponse, cle_indice,
                  cle_chiffree is not null as cle_posee, updated_at
             from fournisseur_ia where code = %s""",
        (code,),
    )


async def retirer_cle(code: str) -> None:
    """Retire la clé et coupe le fournisseur : sans clé, l'activer n'a pas de sens."""
    await execute(
        "update fournisseur_ia set cle_chiffree = null, cle_indice = null, actif = false, "
        "updated_at = now() where code = %s",
        (code,),
    )
    oublier()
