"""Le stockage objet (MinIO) : servir un fichier d'origine en flux."""
import logging

from fastapi.responses import StreamingResponse

from app.core.config import settings
from app.core.errors import NotFound

log = logging.getLogger("ascenda.stockage")


def servir(storage_key: str, *, nom: str, mime: str | None) -> StreamingResponse:
    try:
        from minio import Minio

        client = Minio(
            settings.minio_endpoint,
            access_key=settings.minio_root_user,
            secret_key=settings.minio_root_password,
            secure=settings.minio_secure,
        )
        reponse = client.get_object(settings.minio_bucket, storage_key)
    except Exception as exc:  # noqa: BLE001
        log.warning("Fichier %s illisible : %s", storage_key, exc)
        raise NotFound("Le fichier d'origine n'est pas joignable.") from exc

    def flux():
        try:
            yield from reponse.stream(64 * 1024)
        finally:
            reponse.close()
            reponse.release_conn()

    entetes = {
        # `inline` : un navigateur l'ouvre dans son lecteur plutôt que de le
        # déposer dans les téléchargements.
        "Content-Disposition": f"inline; filename*=UTF-8''{_encoder(nom)}",
    }
    reelle = reponse.headers.get("Content-Length")
    if reelle:
        entetes["Content-Length"] = reelle
    return StreamingResponse(flux(), media_type=mime or "application/pdf", headers=entetes)


def _encoder(nom: str) -> str:
    from urllib.parse import quote

    return quote(nom, safe="")
