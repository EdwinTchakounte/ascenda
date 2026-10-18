"""La réinitialisation de mot de passe par code."""
import hashlib
import logging
import secrets
from datetime import datetime, timedelta, timezone

from app.core.db import connection, execute, fetch_one
from app.core.security import hash_password

log = logging.getLogger("ascenda.mot_de_passe")

VALIDITE = timedelta(minutes=30)
TENTATIVES_MAX = 5
DELAI_ENTRE_DEMANDES = timedelta(minutes=15)


def _hacher(code: str) -> str:
    return hashlib.sha256(code.encode()).hexdigest()


def _normaliser(code: str) -> str:
    """Retire ce que les gens ajoutent en recopiant : espaces, tirets."""
    return "".join(c for c in (code or "") if c.isdigit())


def nouveau_code() -> str:
    """Six chiffres tirés d'une source cryptographique."""
    return f"{secrets.randbelow(1_000_000):06d}"


async def demander(email: str) -> tuple[dict, str] | None:
    """Prépare un code. Retourne (utilisateur, code) ou None."""
    user = await fetch_one(
        "select id, email, display_name, is_active from app_user where lower(email) = %s",
        (email.lower().strip(),),
    )
    if not user or not user["is_active"]:
        return None

    recente = await fetch_one(
        """select 1 from password_reset
            where user_id = %s and created_at > now() - make_interval(mins => %s) limit 1""",
        (user["id"], int(DELAI_ENTRE_DEMANDES.total_seconds() // 60)),
    )
    if recente:
        log.info("Demande de réinitialisation ignorée : trop rapprochée.")
        return None

    code = nouveau_code()
    await execute(
        """insert into password_reset (user_id, code_hash, expires_at)
           values (%s, %s, %s)""",
        (user["id"], _hacher(code), datetime.now(timezone.utc) + VALIDITE),
    )
    return user, code


async def reinitialiser(email: str, code: str, nouveau: str) -> dict | None:
    """Pose le nouveau mot de passe. Retourne l'utilisateur, ou None si refusé."""
    chiffres = _normaliser(code)
    user = await fetch_one(
        "select id, email, display_name, is_active from app_user where lower(email) = %s",
        (email.lower().strip(),),
    )
    if not user or not user["is_active"] or len(chiffres) != 6:
        return None

    async with connection() as conn:
        cur = await conn.execute(
            """select * from password_reset
                where user_id = %s and used_at is null and expires_at > now()
                  and tentatives < %s
                order by created_at desc limit 1
                for update""",
            (user["id"], TENTATIVES_MAX),
        )
        demande = await cur.fetchone()
        if not demande:
            return None

        if demande["code_hash"] != _hacher(chiffres):
            # On compte l'essai avant de refuser : sinon le compteur ne sert à rien.
            await conn.execute(
                "update password_reset set tentatives = tentatives + 1 where id = %s",
                (demande["id"],),
            )
            return None

        await conn.execute(
            "update password_reset set used_at = now() where id = %s", (demande["id"],)
        )
        # Les autres demandes en cours tombent avec celle-ci
        await conn.execute(
            """update password_reset set used_at = now()
                where user_id = %s and used_at is null""",
            (user["id"],),
        )
        await conn.execute(
            "update app_user set password_hash = %s where id = %s",
            (hash_password(nouveau), user["id"]),
        )
        await conn.execute(
            "update refresh_token set revoked_at = now() where user_id = %s and revoked_at is null",
            (user["id"],),
        )

    return user
