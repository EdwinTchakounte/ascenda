"""Inscription, connexion, rafraîchissement, déconnexion."""
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Request, status

from app.core.config import settings
from app.core.db import execute, fetch_one
from app.core.deps import CurrentUser
from app.core.errors import Conflict, Unauthorized
from app.core.security import (
    create_access_token,
    hash_password,
    hash_refresh_token,
    needs_rehash,
    new_refresh_token,
    verify_password,
)
from app.schemas.auth import (
    ChangerMotDePasseIn,
    ConnexionIn,
    InscriptionIn,
    Jetons,
    MotDePasseOublieIn,
    RafraichirIn,
    ReinitialiserIn,
    SessionOuverte,
    Utilisateur,
)
from app.services import mot_de_passe

log = logging.getLogger("ascenda.auth")

router = APIRouter(prefix="/auth", tags=["Authentification"])


def _utilisateur(row: dict) -> Utilisateur:
    return Utilisateur(
        id=str(row["id"]),
        email=row.get("email"),
        nom=row.get("display_name"),
        plan=row["plan"],
        plan_until=row.get("plan_until"),
        locale=row.get("locale") or "fr",
        cree_le=row["created_at"],
    )


async def _ouvrir_session(user: dict, request: Request) -> SessionOuverte:
    raw, empreinte, expire = new_refresh_token()
    await execute(
        """insert into refresh_token (user_id, token_hash, expires_at, user_agent, ip)
           values (%s, %s, %s, %s, %s)""",
        (
            user["id"],
            empreinte,
            expire,
            (request.headers.get("user-agent") or "")[:300],
            request.client.host if request.client else None,
        ),
    )
    await execute("update app_user set last_login_at = now() where id = %s", (user["id"],))
    return SessionOuverte(
        utilisateur=_utilisateur(user),
        jetons=Jetons(
            access_token=create_access_token(user["id"], user["plan"]),
            refresh_token=raw,
            expire_dans=settings.access_token_minutes * 60,
        ),
    )


@router.post("/inscription", response_model=SessionOuverte, status_code=status.HTTP_201_CREATED)
async def inscription(data: InscriptionIn, request: Request):
    email = data.email.lower().strip()
    if await fetch_one("select 1 from app_user where lower(email) = %s", (email,)):
        raise Conflict("Un compte existe déjà avec cette adresse. Essayez de vous connecter.")
    user = await fetch_one(
        """insert into app_user (email, display_name, password_hash, plan, email_verified)
           values (%s, %s, %s, 'free', false)
           returning id, email, display_name, plan, plan_until, locale, created_at""",
        (email, data.nom, hash_password(data.mot_de_passe)),
    )
    # Le mot de bienvenue ne conditionne pas l'ouverture du compte : si le
    # service de courriel est en panne, on ne va pas refuser une inscription.
    try:
        from app.services.courriel import evenements

        await evenements.bienvenue(user)
    except Exception:  # noqa: BLE001
        log.exception("Courriel de bienvenue non envoyé à %s", email)

    return await _ouvrir_session(user, request)


@router.post("/connexion", response_model=SessionOuverte)
async def connexion(data: ConnexionIn, request: Request):
    user = await fetch_one(
        """select id, email, display_name, password_hash, plan, plan_until, locale,
                  is_active, created_at
           from app_user where lower(email) = %s""",
        (data.email.lower().strip(),),
    )
    # Même message dans les deux cas : ne pas révéler quelles adresses ont un compte.
    if not user or not verify_password(data.mot_de_passe, user.get("password_hash")):
        raise Unauthorized("Adresse ou mot de passe incorrect.")
    if not user["is_active"]:
        raise Unauthorized("Ce compte est désactivé.")
    if needs_rehash(user["password_hash"]):
        await execute(
            "update app_user set password_hash = %s where id = %s",
            (hash_password(data.mot_de_passe), user["id"]),
        )
    return await _ouvrir_session(user, request)


@router.post("/rafraichir", response_model=Jetons)
async def rafraichir(data: RafraichirIn):
    """Rotation du refresh : l'ancien jeton est révoqué à l'usage.

    Une connexion irrégulière peut faire échouer la réponse après révocation ;
    le client doit alors repasser par /auth/connexion. C'est le prix d'une
    rotation stricte, et c'est le bon compromis pour un jeton de 60 jours.
    """
    empreinte = hash_refresh_token(data.refresh_token)
    ligne = await fetch_one(
        """select rt.id, rt.user_id, rt.expires_at, rt.revoked_at, u.plan, u.is_active
           from refresh_token rt join app_user u on u.id = rt.user_id
           where rt.token_hash = %s""",
        (empreinte,),
    )
    if not ligne or ligne["revoked_at"] or not ligne["is_active"]:
        raise Unauthorized("Session invalide. Reconnectez-vous.")
    if ligne["expires_at"] < datetime.now(timezone.utc):
        raise Unauthorized("Session expirée. Reconnectez-vous.")

    raw, nouvelle_empreinte, expire = new_refresh_token()
    await execute("update refresh_token set revoked_at = now() where id = %s", (ligne["id"],))
    await execute(
        "insert into refresh_token (user_id, token_hash, expires_at) values (%s, %s, %s)",
        (ligne["user_id"], nouvelle_empreinte, expire),
    )
    return Jetons(
        access_token=create_access_token(ligne["user_id"], ligne["plan"]),
        refresh_token=raw,
        expire_dans=settings.access_token_minutes * 60,
    )


@router.post("/deconnexion", status_code=status.HTTP_204_NO_CONTENT)
async def deconnexion(data: RafraichirIn, user: CurrentUser):
    await execute(
        """update refresh_token set revoked_at = now()
           where token_hash = %s and user_id = %s and revoked_at is null""",
        (hash_refresh_token(data.refresh_token), user["id"]),
    )


@router.post("/deconnexion-partout", status_code=status.HTTP_204_NO_CONTENT)
async def deconnexion_partout(user: CurrentUser):
    await execute(
        "update refresh_token set revoked_at = now() where user_id = %s and revoked_at is null",
        (user["id"],),
    )


@router.post("/mot-de-passe-oublie", status_code=status.HTTP_204_NO_CONTENT,
             summary="Demander un code de réinitialisation")
async def mot_de_passe_oublie(data: MotDePasseOublieIn):
    """Répond toujours 204, que l'adresse existe ou non.

    Distinguer les deux cas transformerait cette route en annuaire : on
    saurait, adresse par adresse, qui a un compte chez nous.
    """
    resultat = await mot_de_passe.demander(data.email)
    if resultat:
        user, code = resultat
        try:
            from app.services.courriel import envoyer

            await envoyer(
                "mot_de_passe_oublie",
                destinataire=user["email"],
                user_id=str(user["id"]),
                contexte={"code": code,
                          "minutes": int(mot_de_passe.VALIDITE.total_seconds() // 60)},
            )
        except Exception:  # noqa: BLE001
            log.exception("Code de réinitialisation non envoyé.")


@router.post("/mot-de-passe-reinitialiser", status_code=status.HTTP_204_NO_CONTENT,
             summary="Poser un nouveau mot de passe avec le code reçu")
async def reinitialiser_mot_de_passe(data: ReinitialiserIn):
    user = await mot_de_passe.reinitialiser(data.email, data.code, data.nouveau)
    if not user:
        # Un seul message pour le code faux, expiré, déjà servi ou trop essayé :
        # préciser lequel aiderait surtout celui qui essaie des codes.
        raise Unauthorized("Ce code n'est pas valable. Demandez-en un nouveau.")
    try:
        from app.services.courriel import envoyer

        await envoyer("mot_de_passe_change", destinataire=user["email"],
                      user_id=str(user["id"]), contexte={})
    except Exception:  # noqa: BLE001
        log.exception("Avis de changement de mot de passe non envoyé.")


@router.get("/moi", response_model=Utilisateur)
async def moi(user: CurrentUser):
    return _utilisateur(user)


@router.post("/mot-de-passe", status_code=status.HTTP_204_NO_CONTENT)
async def changer_mot_de_passe(data: ChangerMotDePasseIn, user: CurrentUser):
    ligne = await fetch_one("select password_hash from app_user where id = %s", (user["id"],))
    if not verify_password(data.ancien, ligne.get("password_hash")):
        raise Unauthorized("Mot de passe actuel incorrect.")
    await execute(
        "update app_user set password_hash = %s where id = %s",
        (hash_password(data.nouveau), user["id"]),
    )
    try:
        from app.services.courriel import envoyer

        await envoyer("mot_de_passe_change", destinataire=user.get("email") or "",
                      user_id=str(user["id"]), contexte={})
    except Exception:  # noqa: BLE001
        log.exception("Avis de changement de mot de passe non envoyé.")

    # Changer de mot de passe ferme les autres sessions : c'est ce qu'on attend
    # quand on le change parce qu'on le croit compromis.
    await execute(
        "update refresh_token set revoked_at = now() where user_id = %s and revoked_at is null",
        (user["id"],),
    )
