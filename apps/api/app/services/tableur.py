"""Servir une liste de la console en fichier de tableur."""
import csv
import io
from collections.abc import Iterable
from datetime import date, datetime
from urllib.parse import quote

from fastapi.responses import StreamingResponse

SEPARATEUR = ";"


def _cellule(v) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "oui" if v else "non"
    if isinstance(v, datetime):
        # Sans fuseau et à la seconde : un tableur ne sait pas lire un décalage.
        return v.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(v, date):
        return v.strftime("%Y-%m-%d")
    return str(v)


def servir(nom: str, entetes: list[str], lignes: Iterable[Iterable]) -> StreamingResponse:
    """Un téléchargement nommé, écrit au fur et à mesure."""

    def flux():
        tampon = io.StringIO()
        plume = csv.writer(tampon, delimiter=SEPARATEUR, quoting=csv.QUOTE_MINIMAL,
                           lineterminator="\r\n")

        def vider() -> str:
            texte = tampon.getvalue()
            tampon.seek(0)
            tampon.truncate(0)
            return texte

        yield "﻿" + f"sep={SEPARATEUR}\r\n"
        plume.writerow(entetes)
        yield vider()
        for ligne in lignes:
            plume.writerow([_cellule(v) for v in ligne])
            yield vider()

    horodate = datetime.now().strftime("%Y-%m-%d_%Hh%M")
    fichier = f"ascenda-{nom}-{horodate}.csv"
    return StreamingResponse(
        flux(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(fichier)}"},
    )
