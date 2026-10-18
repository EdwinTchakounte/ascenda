"""Saisir un code : code d'accès ou code ambassadeur."""
import logging
import re
import secrets
import unicodedata
from datetime import datetime, timedelta, timezone

from app.core.db import connection, execute, fetch_one
from app.core.errors import ApiError, Conflict, NotFound
from app.services import exploitation

log = logging.getLogger("ascenda.codes")

# Sans 0, O, 1, I ni L : un code dicté au téléphone ou recopié d'une capture d'écran ne
_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

INTROUVABLE = "Ce code n'existe pas. Vérifiez qu'il est bien recopié."


class CodeRefuse(ApiError):
    def __init__(self, detail: str):
        super().__init__(detail, 422, "code_refuse")


def normaliser(brut: str | None) -> str:
    """« lancement 2026 » devient « LANCEMENT2026 »."""
    return re.sub(r"\s+", "", (brut or "")).upper()


def _racine(nom: str | None, email: str | None) -> str:
    source = (nom or "").strip().split(" ")[0] or (email or "").split("@")[0]
    ascii_ = unicodedata.normalize("NFKD", source).encode("ascii", "ignore").decode()
    lettres = re.sub(r"[^A-Za-z]", "", ascii_).upper()[:6]
    return lettres if len(lettres) >= 2 else "ASC"


async def code_ambassadeur(user: dict) -> str:
    """Le code du lecteur, créé à la première demande et stable ensuite."""
    ligne = await fetch_one(
        "select code_parrainage, display_name, email from app_user where id = %s", (user["id"],))
    if ligne and ligne["code_parrainage"]:
        return ligne["code_parrainage"]
    racine = _racine(ligne.get("display_name") if ligne else None, ligne.get("email") if ligne else None)
    for _ in range(12):
        code = f"{racine}-{''.join(secrets.choice(_ALPHABET) for _ in range(4))}"
        if await fetch_one("select 1 from code_acces where code = %s", (code,)):
            continue
        pose = await fetch_one(
            """update app_user set code_parrainage = %s
                where id = %s and code_parrainage is null
                  and not exists (select 1 from app_user where code_parrainage = %s)
            returning code_parrainage""",
            (code, user["id"], code),
        )
        if pose:
            return pose["code_parrainage"]
        deja = await fetch_one("select code_parrainage from app_user where id = %s", (user["id"],))
        if deja and deja["code_parrainage"]:
            return deja["code_parrainage"]
    raise Conflict("Le code ambassadeur n'a pas pu être créé. Réessayez.")


def _fin_acces(code: dict, maintenant: datetime) -> datetime:
    if code["duree_jours"]:
        return min(code["fin"], maintenant + timedelta(days=code["duree_jours"]))
    return code["fin"]


async def _verifier_acces(code: dict, user_id: str | None) -> None:
    maintenant = datetime.now(timezone.utc)
    if not code["actif"]:
        raise CodeRefuse("Ce code n'est plus actif.")
    if code["debut"] > maintenant:
        raise CodeRefuse("Ce code n'est pas encore ouvert.")
    if code["fin"] <= maintenant:
        raise CodeRefuse("Ce code a expiré : il ne produit plus d'effet.")
    if code["max_utilisations"]:
        n = await fetch_one("select count(*) as n from code_acces_utilisation where code_id = %s",
                            (code["id"],))
        if n["n"] >= code["max_utilisations"]:
            raise CodeRefuse("Ce code a atteint son nombre maximal d'utilisations.")
    if user_id and await fetch_one(
        "select 1 from code_acces_utilisation where code_id = %s and user_id = %s",
        (code["id"], user_id),
    ):
        raise Conflict("Vous avez déjà activé ce code.")


async def verifier(brut: str, user_id: str | None = None) -> dict:
    """Dit ce que ferait ce code, sans rien écrire. Lève si le code est refusé."""
    code = normaliser(brut)
    if not code:
        raise NotFound(INTROUVABLE)
    acces = await fetch_one("select * from code_acces where code = %s", (code,))
    if acces:
        await _verifier_acces(acces, user_id)
        return {"type": "acces", "code": acces}
    parrain = await fetch_one(
        "select id, email, display_name, code_parrainage from app_user where code_parrainage = %s and is_active",
        (code,),
    )
    if parrain:
        if not (await exploitation.parrainage())["actif"]:
            raise CodeRefuse("Le programme ambassadeur est suspendu pour le moment. "
                             "Créez votre compte sans code.")
        if user_id and str(parrain["id"]) == str(user_id):
            raise CodeRefuse("Ce code est le vôtre : il sert à inviter d'autres lecteurs.")
        return {"type": "parrainage", "parrain": parrain}
    raise NotFound(INTROUVABLE)


async def activer_acces(user: dict, brut: str, origine: str) -> dict:
    """Active un code d'accès pour ce compte."""
    trouve = await verifier(brut, str(user["id"]))
    if trouve["type"] != "acces":
        raise CodeRefuse("Un code ambassadeur se saisit à la création du compte. "
                         "Celui-ci ne peut plus être utilisé sur un compte déjà ouvert.")
    return await _poser_acces(user, trouve["code"], origine)


async def _poser_acces(user: dict, code: dict, origine: str) -> dict:
    maintenant = datetime.now(timezone.utc)
    async with connection() as conn:
        async with conn.transaction():
            cur = await conn.execute("select * from code_acces where id = %s for update", (code["id"],))
            frais = await cur.fetchone()
            await _verifier_acces(frais, str(user["id"]))
            fin = _fin_acces(frais, maintenant)
            await conn.execute(
                """insert into code_acces_utilisation (code_id, user_id, fin, origine)
                   values (%s, %s, %s, %s)""",
                (frais["id"], user["id"], fin, origine),
            )
    from app.services.acces import FONCTIONS

    fonctions = list(FONCTIONS) if code["niveau"] == "complet" else list(code["fonctions"])
    return {
        "type": "acces",
        "code": code["code"],
        "libelle": code["libelle"],
        "niveau": code["niveau"],
        "fonctions": [{"cle": f, "libelle": FONCTIONS.get(f, f)} for f in fonctions],
        "fin": fin,
        "message": (f"Code {code['code']} activé : "
                    + ("tout Ascension" if code["niveau"] == "complet" else "accès limité")
                    + f" jusqu'au {fin.day:02d}/{fin.month:02d}/{fin.year}."),
    }


async def appliquer_a_l_inscription(user: dict, trouve: dict) -> dict:
    """Applique un code déjà vérifié au compte qui vient d'être créé."""
    if trouve["type"] == "acces":
        return await _poser_acces(user, trouve["code"], "inscription")
    return await _parrainer(user, trouve["parrain"])


async def _parrainer(filleul: dict, parrain: dict) -> dict:
    reglage = await exploitation.parrainage()
    expire = datetime.now(timezone.utc) + timedelta(days=reglage["validite_jours"])
    await execute("update app_user set parrain_id = %s where id = %s and parrain_id is null",
                  (parrain["id"], filleul["id"]))
    bon = await fetch_one(
        """insert into bon_reduction (user_id, filleul_id, pourcent, expire_le)
           values (%s, %s, %s, %s)
           on conflict do nothing returning *""",
        (parrain["id"], filleul["id"], reglage["pourcent"], expire),
    )
    if bon:
        try:
            from app.services.courriel import evenements

            await evenements.parrainage_recompense(parrain, filleul, bon)
        except Exception:  # noqa: BLE001
            log.exception("Avis de parrainage non envoyé à %s", parrain.get("email"))
    prenom = ((parrain.get("display_name") or "").strip().split(" ") or [""])[0]
    return {
        "type": "parrainage",
        "code": parrain["code_parrainage"],
        "message": (f"Vous avez rejoint ASCENDA grâce à {prenom}. Merci à vous deux."
                    if prenom else "Code ambassadeur pris en compte. Bienvenue."),
    }


# ------------------------------------------------------------ les réductions

async def bon_disponible(user_id: str) -> dict | None:
    """Le bon qui s'appliquera au prochain paiement : celui qui expire le premier."""
    return await fetch_one(
        """select b.* from bon_reduction b
            where b.user_id = %s and b.utilise_le is null and b.expire_le > now()
              and not exists (select 1 from payment p
                               where p.bon_id = b.id and p.statut in ('en_attente', 'valide'))
            order by b.expire_le limit 1""",
        (user_id,),
    )


def montant_reduit(montant: int, pourcent: int) -> int:
    """Arrondi à la dizaine inférieure, jamais sous 10 XAF."""
    brut = montant * (100 - pourcent) / 100
    return max(10, int(brut // 10) * 10)
