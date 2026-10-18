#!/usr/bin/env python3
"""Produit `memento-agronome.json`, la structure du Mémento de l'agronome."""
import json
import re
import sys
import unicodedata
from pathlib import Path

import pymupdf

RACINE = Path(__file__).resolve().parents[3]
PDF = RACINE / "livres" / "Memento-de-l-Agronome_C@Moriarty.pdf"
SORTIE = Path(__file__).with_name("memento-agronome.json")
DECALAGE = 4
PAGES_SOMMAIRE = (8, 9, 10)          # index 0 : pages 9 à 11 du PDF
DEBUT_TEXTE, DEBUT_ANNEXES = 13, 1651

CAPITALES = "A-ZÀÂÉÈÊËÎÏÔÛÙÇŒ"
SECTION = re.compile(
    rf"^((?:LE|LA|LES|L[’']|UN|UNE|DES|DU|QUELQUES)\s?[{CAPITALES}][{CAPITALES}’' \-,:()?]{{2,90}}?)\d{{0,2}}$")
LATIN = re.compile(r"^[A-Z]{4,} [A-Z]{4,}$")

# Les noms propres et sigles que la mise en minuscules effacerait.
PROPRES = {
    "angole": "Angole", "madagascar": "Madagascar", "guinée": "Guinée", "para": "Para", "rhodes": "Rhodes",
    "caraïbes": "Caraïbes", "indes": "Indes", "cap": "Cap", "job": "Job", "mali": "Mali", "sénégal": "Sénégal",
    "amérique": "Amérique", "afrique": "Afrique", "ouest": "Ouest", "chine": "Chine", "asie": "Asie",
}


def plier(s: str) -> str:
    # L'apostrophe courbe disparaîtrait à la conversion ASCII et collerait les mots («
    s = s.replace("’", " ").replace("'", " ")
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", s)).strip()


def casse(titre: str) -> str:
    """« L'ÉLEVAGE DES BOVINS DE TRAIT » -> « L'élevage des bovins de trait »."""
    bas = titre.lower()
    bas = re.sub(r"[a-zà-ÿœ\-]+", lambda m: PROPRES.get(m.group(0), m.group(0)), bas)
    return bas[0].upper() + bas[1:]


GENERIQUES = {"quelques definitions", "les definitions", "des definitions utiles", "les maladies",
              "l alimentation", "la reproduction", "les performances", "quelques reperes"}


# Un parent lui-même générique ne nomme rien : on remonte d'un cran.
PORTEURS = {"Les caractéristiques générales": "Les cultures fourragères"}


def lire_sommaire(doc) -> list[dict]:
    texte = "\n".join(l.strip() for p in PAGES_SOMMAIRE for l in doc[p].get_text().splitlines())
    entrees = []
    motif = r"^((?:\d[ \t]?\.?[ \t]?)+\d?\.?|INTRODUCTION|ANNEXES)[ \t]*(.*?)\s*(?:\.\s?){3,}\s*\n?\s*(\d{1,4})\s*$"
    for num, titre, page in re.findall(motif, texte, re.M):
        n = re.sub(r"\s", "", num).rstrip(".")
        if n == "43":                      # « 4 3. Modifier les itinéraires techniques »
            n = "4.3"
        if not re.match(r"\d", n):
            n, titre = "", (titre or num)
        titre = titre.strip()
        if titre.isupper():
            titre = casse(titre)
        page_pdf = int(page) + DECALAGE
        if page_pdf >= DEBUT_ANNEXES and n in ("1", "2", "3", "4"):
            n = "A" + n                    # les annexes numérotées 1 à 4
        niveau = 1 if not n else (2 if n.startswith("A") else n.count(".") + 1)
        entrees.append({"num": n, "titre": titre.strip(), "niveau": niveau, "page": page_pdf, "type": "sommaire"})
    return entrees


def sections(doc, sommaire: list[dict]) -> list[dict]:
    couvertures = {e["page"] for e in sommaire if e["niveau"] == 1}
    trouvees = []
    for pi in range(DEBUT_TEXTE - 1, DEBUT_ANNEXES - 1):
        if pi + 1 in couvertures:
            continue
        lignes = [l.strip() for l in doc[pi].get_text().splitlines() if l.strip()]
        for i, l in enumerate(lignes):
            parent = max((e for e in sommaire if e["page"] <= pi + 1), key=lambda e: (e["page"], e["niveau"]))
            m = SECTION.match(l)
            if m and len(l) > 3:
                titre = m.group(1).strip(" :")
            elif (LATIN.match(l) and i + 1 < len(lignes) and lignes[i + 1].lower().startswith(l.lower())):
                titre = l
            else:
                continue
            if plier(titre) in plier(parent["titre"]) and abs(parent["page"] - (pi + 1)) <= 2:
                continue                    # le titre du chapitre répété en tête
            lisible = casse(titre)
            if plier(titre) in GENERIQUES:
                porteur = PORTEURS.get(parent["titre"], parent["titre"])
                lisible = f"{porteur} : {lisible[0].lower()}{lisible[1:]}"
            # `ligne` : le titre tel qu'imprimé
            trouvees.append({"num": "", "titre": lisible, "niveau": parent["niveau"] + 1,
                             "page": pi + 1, "type": "section", "ligne": l, "_parent": parent["num"]})
    return trouvees


def axe(num: str) -> str | None:
    if num == "":
        return "12-1-developpement-rural"     # l'introduction et ses sections
    if num is None:
        return None
    if num.startswith("A"):
        return "12-2-agronomie-exploitation" if num == "A1" else None   # formulaires ; adresses, index, cédéroms : non
    if num == "5.4":
        return None                                                     # glossaire
    if num in ("1", "2") or num.startswith(("1.", "2.")):
        return "12-1-developpement-rural"
    if num in ("4.3.5", "4.3.6", "5.3.3"):
        return "12-3-protection-cultures"
    if num == "3" or num.startswith("3.") or num.startswith("4"):
        return "12-2-agronomie-exploitation"
    if num.startswith("5"):
        return "12-4-cultures-plantes"
    if num.startswith("7.3"):
        return "12-6-pisciculture-petits-elevages"
    if num.startswith(("6", "7")):
        return "12-5-elevage-sante-animale"
    return None


def main() -> None:
    doc = pymupdf.open(PDF)
    sommaire = lire_sommaire(doc)
    if len(sommaire) != 89:
        sys.exit(f"Sommaire : {len(sommaire)} entrées lues, 89 attendues. Rien n'est écrit.")
    mal_formes = [e for e in sommaire if e["num"] and not re.fullmatch(r"(A[1-4]|[1-7](\.\d){0,2})", e["num"])]
    if mal_formes:
        sys.exit(f"Numéros de sommaire mal lus : {[(e['num'], e['titre']) for e in mal_formes]}. Rien n'est écrit.")
    tout = sorted(sommaire + sections(doc, sommaire), key=lambda e: (e["page"], e["type"] != "sommaire", e["niveau"]))
    for e in tout:
        num = e["num"] if e["type"] == "sommaire" else e.pop("_parent")
        e["axe"] = None if e["titre"] == "Annexes" else axe(num)
        if e["titre"] in ("1", "Formulaires") or (e["num"] == "A1"):
            e["titre"] = "Formulaires"
    SORTIE.write_text(json.dumps({
        "fichier": PDF.name,
        "titre": "Mémento de l'agronome",
        "auteurs": ["CIRAD", "GRET", "Ministère des Affaires étrangères"],
        "annee": 2002,
        "editeur": "CIRAD, GRET, ministère des Affaires étrangères",
        "langue": "fr",
        "decalage_pages": DECALAGE,
        "note": "Produit par memento_agronome.py. page = page du PDF (imprimée + 4). axe = sous-axe du pôle "
                "Agriculture et élevage ; null = hors parcours.",
        "chapitres": tout,
    }, ensure_ascii=False, indent=1))
    from collections import Counter
    print(f"{len(sommaire)} entrées de sommaire, {len(tout) - len(sommaire)} sections : {len(tout)} chapitres")
    print(Counter(e["axe"] for e in tout))


if __name__ == "__main__":
    main()
