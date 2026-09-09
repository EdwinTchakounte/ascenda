"""Mots de passe (argon2) et jetons (JWT).

Deux jetons : un access court porté par l'en-tête Authorization, un refresh long
stocké haché en base. Révoquer une session revient alors à marquer une ligne,
sans changer le secret global ni déconnecter tout le monde.
"""
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from app.core.config import settings

_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, stored_hash: str | None) -> bool:
    if not stored_hash:
        return False
    try:
        return _hasher.verify(stored_hash, password)
    except (VerifyMismatchError, InvalidHashError):
        return False


def needs_rehash(stored_hash: str) -> bool:
    try:
        return _hasher.check_needs_rehash(stored_hash)
    except InvalidHashError:
        return True


def _encode(payload: dict[str, Any], expires: timedelta, kind: str) -> str:
    now = datetime.now(timezone.utc)
    body = {**payload, "iat": now, "exp": now + expires, "typ": kind}
    return jwt.encode(body, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_access_token(user_id: str, plan: str) -> str:
    return _encode(
        {"sub": str(user_id), "plan": plan},
        timedelta(minutes=settings.access_token_minutes),
        "access",
    )


def decode_access_token(token: str) -> dict[str, Any] | None:
    try:
        claims = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except jwt.PyJWTError:
        return None
    if claims.get("typ") != "access":
        return None
    return claims


def new_refresh_token() -> tuple[str, str, datetime]:
    """Retourne (jeton en clair, empreinte stockée, expiration)."""
    raw = secrets.token_urlsafe(48)
    return raw, hash_refresh_token(raw), datetime.now(timezone.utc) + timedelta(
        days=settings.refresh_token_days
    )


def hash_refresh_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()
