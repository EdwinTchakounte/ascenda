"""Servir une liste de la console en fichier de tableur.

Deux choix qui n'en ont pas l'air, et qui décident si le fichier s'ouvre
proprement ou pas du tout.

Le point-virgule comme séparateur, et non la virgule : un tableur configuré
en français lit la virgule comme séparateur décimal et verse toute la ligne
dans une seule cellule. La ligne `sep=;` posée en tête le dit explicitement,
ce qu'Excel comprend et ce que LibreOffice ignore sans dommage.

La marque d'ordre des octets en tête, parce qu'un tableur qui ne la trouve pas
suppose l'encodage de la machine : « modifié » devient « modifiÃ© ».

Le fichier est produit en flux, ligne par ligne : un journal de cent mille
lignes ne doit pas être assemblé en mémoire avant d'être envoyé.
"""
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
