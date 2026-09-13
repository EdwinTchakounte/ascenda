"""Point d'entrée de l'API ASCENDA."""
import asyncio
import logging
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse

from app.core.config import settings
from app.core.db import close_pool, fetch_one, open_pool
from app.routers import (
    admin,
    admin_codes,
    agent,
    axes,
    bibliotheque,
    chronogramme,
    codes,
    compte,
    concepts,
    lecteur,
    notes,
    paiement,
    progression,
    quiz,
    recherche,
)
from app.routers import auth as auth_router
from app.services import ordonnanceur
# Aliasé : `recherche` est déjà le nom du routeur importé plus haut.
from app.services import recherche as service_recherche

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s | %(message)s")
log = logging.getLogger("ascenda")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await open_pool()
    log.info("Connecté à %s:%s/%s", settings.postgres_host, settings.postgres_port, settings.postgres_db)
    taches = ordonnanceur.demarrer()
    # Le modèle de recherche se charge en fond : quarante secondes que le
    # premier lecteur n'a pas à payer. La tâche ne bloque pas le démarrage.
    taches.append(asyncio.create_task(service_recherche.prechauffer(), name="prechauffage"))
    try:
        yield
    finally:
        await ordonnanceur.arreter(taches)
        await close_pool()


app = FastAPI(
    title="ASCENDA",
    description=(
        "API de lecture guidée. Un corpus de 78 ouvrages, un chronogramme adaptatif, "
        "et un agent qui cite toujours le livre et la page."
    ),
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs",
    openapi_url="/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Ce qui reste joignable pendant une maintenance : la sonde, l'état, la
# documentation, et le webhook de paiement. Fermer le webhook ferait rejouer
# Tara en boucle et pourrait faire abandonner un paiement déjà débité.
_OUVERT_EN_MAINTENANCE = (
    "/sante",
    "/v1/etat",
    "/docs",
    "/openapi.json",
    # Tara rejouerait en boucle sur un refus, et pourrait finir par abandonner
    # un paiement déjà débité. Le webhook reste donc ouvert : il n'écrit que
    # dans les tables de paiement, qu'on ne migre pas en même temps que le reste.
    "/v1/paiements/webhook/",
    # Se connecter et rafraîchir restent possibles. Ces deux routes n'écrivent
    # que dans `refresh_token`. Les fermer transformerait une maintenance de dix
    # minutes en vague de reconnexions : les jetons d'accès expirent au bout
    # d'une demi-heure, et l'utilisateur se retrouverait déconnecté sans
    # pouvoir revenir, bien après la fin de la mise à jour.
    "/v1/auth/connexion",
    "/v1/auth/rafraichir",
)


@app.middleware("http")
async def garde_maintenance(request: Request, call_next):
    """Refuse les écritures pendant une mise à jour.

    L'écran figé côté application est une courtoisie ; ce refus est la
    garantie. Un client qui ignorerait le drapeau, ou qui ne l'a pas encore lu,
    ne peut pas écrire dans une base qu'on est en train de migrer.

    La lecture reste ouverte : quelqu'un qui lisait un chapitre au moment de la
    bascule peut le finir.
    """
    if request.method in ("GET", "HEAD", "OPTIONS"):
        return await call_next(request)
    if request.url.path.startswith(_OUVERT_EN_MAINTENANCE):
        return await call_next(request)

    from app.services import exploitation

    try:
        m = await exploitation.maintenance()
    except Exception:  # noqa: BLE001
        # Réglages illisibles : on laisse passer. Une panne de lecture ne doit
        # pas fermer le service.
        return await call_next(request)

    if m["actif"]:
        return JSONResponse(
            status_code=503,
            headers={"Retry-After": "300"},
            content={
                "code": "maintenance",
                "message": m.get("message") or "ASCENDA est en cours de mise à jour.",
                "jusqu_au": m.get("jusqu_au"),
            },
        )
    return await call_next(request)


@app.exception_handler(Exception)
async def erreur_inattendue(request: Request, exc: Exception):
    log.exception("Erreur non gérée sur %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={
            "code": "erreur_serveur",
            "message": "Une erreur inattendue est survenue. Réessayez dans un instant.",
        },
    )


@app.get("/sante", tags=["Service"])
async def sante():
    """Vérifie que l'API répond et que la base est joignable."""
    try:
        await fetch_one("select 1 as ok")
        base = "ok"
    except Exception as exc:  # noqa: BLE001, on veut le message dans la réponse
        base = f"indisponible: {exc}"
    return {"service": "ascenda-api", "version": app.version, "base": base, "env": settings.api_env}


@app.get("/admin", include_in_schema=False)
async def page_admin():
    """Le tableau de bord d'exploitation, servi par l'API elle-même.

    Une page, pas une application. La faire vivre dans la vitrine aurait obligé
    celle-ci à porter une session, alors qu'elle n'a délibérément rien à savoir
    de personne ; en faire un troisième déploiement aurait ajouté une brique à
    surveiller pour un écran qu'on ouvre le matin. Elle voyage donc avec l'image
    de l'API, sans construction ni dépendance.

    Elle n'est pas indexable et ne donne rien sans un compte porteur du droit
    d'administration, qui se pose à la main en base.
    """
    return FileResponse(
        Path(__file__).parent / "statique" / "admin.html",
        media_type="text/html; charset=utf-8",
        headers={"X-Robots-Tag": "noindex, nofollow"},
    )


@app.get("/v1/etat", tags=["Service"], summary="L'état d'exploitation")
async def etat():
    """Ce que les applications lisent pour savoir dans quel monde elles vivent.

    Trois réponses en un appel : sommes-nous en période de lancement, sommes-nous
    en maintenance, et cette version de l'application est-elle encore acceptée.
    Publique et sans jeton : une application qui ne peut pas se connecter doit
    quand même pouvoir apprendre pourquoi.
    """
    from app.services import exploitation

    return await exploitation.etat()


for r in (
    admin.router,
    admin_codes.router,
    auth_router.router,
    axes.router,
    bibliotheque.router,
    lecteur.router,
    recherche.router,
    agent.router,
    quiz.router,
    chronogramme.router,
    progression.router,
    notes.router,
    concepts.router,
    paiement.router,
    compte.router,
    codes.router,
):
    app.include_router(r, prefix="/v1")
