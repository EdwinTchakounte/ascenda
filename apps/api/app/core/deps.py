"""Dépendances FastAPI : identification de l'appelant et garde-fous d'usage."""
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.db import acteur, fetch_one
from app.core.errors import Forbidden, Unauthorized
from app.core.security import decode_access_token

_bearer = HTTPBearer(auto_error=False)
_bearer_optional = HTTPBearer(auto_error=False)


async def _load_user(token: str | None) -> dict | None:
    if not token:
        return None
    claims = decode_access_token(token)
    if not claims:
        return None
    user = await fetch_one(
        """select id, email, display_name, plan, plan_until, is_active, locale,
                  created_at, est_admin
           from app_user where id = %s""",
        (claims["sub"],),
    )
    if not user or not user["is_active"]:
        return None
    # Le journal des modifications nomme l'auteur de l'écriture, pas la route.
    acteur.set(("administrateur " if user["est_admin"] else "") + (user["email"] or str(user["id"])))
    return user


async def current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> dict:
    user = await _load_user(credentials.credentials if credentials else None)
    if user is None:
        raise Unauthorized()
    return user


async def optional_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_optional)],
) -> dict | None:
    """Pour les routes publiques qui s'enrichissent quand l'appelant est connu
    (la bibliothèque affiche la progression si l'on sait qui regarde)."""
    return await _load_user(credentials.credentials if credentials else None)


async def premium_user(user: Annotated[dict, Depends(current_user)]) -> dict:
    """Toutes les fonctions d'Ascension : abonnement, lancement ou code complet."""
    from app.services import acces

    if not (await acces.etat(user))["complet"]:
        raise Forbidden(
            "Cette fonction fait partie de l'offre Ascension. "
            "Vous pouvez en profiter en changeant de formule depuis votre compte."
        )
    return user


def exige(fonction: str):
    """Une dépendance qui demande une fonction précise, et non tout Ascension."""

    async def verifier(user: Annotated[dict, Depends(current_user)]) -> dict:
        from app.services import acces

        if not await acces.a_droit(user, fonction):
            raise Forbidden(
                "Cette fonction fait partie de l'offre Ascension. "
                "Un abonnement ou un code d'accès l'ouvre depuis votre profil."
            )
        return user

    return verifier


async def admin_user(user: Annotated[dict, Depends(current_user)]) -> dict:
    """Le droit d'administration, posé à la main en base et jamais accordé par
    une route. Le message ne dit pas qu'il existe un espace d'administration :
    une réponse qui renseigne est une réponse qui aide à chercher."""
    if not user.get("est_admin"):
        raise Forbidden("Vous n'avez pas accès à cette ressource.")
    return user


CurrentUser = Annotated[dict, Depends(current_user)]
OptionalUser = Annotated[dict | None, Depends(optional_user)]
PremiumUser = Annotated[dict, Depends(premium_user)]
AdminUser = Annotated[dict, Depends(admin_user)]


CLIENTS_APPLICATION = {"android", "ios"}


def client_application(request: Request) -> bool:
    return request.headers.get("x-ascenda-client", "").lower() in CLIENTS_APPLICATION


ClientApplication = Annotated[bool, Depends(client_application)]
