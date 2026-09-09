"""Point d'entrée de l'API ASCENDA."""
import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.core.db import close_pool, fetch_one, open_pool
from app.routers import (
    agent,
    axes,
    bibliotheque,
    chronogramme,
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


for r in (
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
):
    app.include_router(r, prefix="/v1")
