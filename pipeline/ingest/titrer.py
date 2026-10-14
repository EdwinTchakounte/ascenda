#!/usr/bin/env python3
"""Relève dans les ouvrages le nom des divisions que l'extraction n'a pas vues.

Produit `titres_par_pages.json`, lu par `app.outils.corriger_corpus` : chaque
chapitre nommé par ses pages prend le nom de la division qui le contient.
Les pages viennent des ouvrages ; les intitulés sont relus, la numérisation
perdant les accents sur plusieurs d'entre eux.
"""
import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

import pymupdf

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import LIVRES  # noqa: E402

SORTIE = Path(__file__).resolve().parents[2] / "apps/api/app/outils/titres_par_pages.json"

LISEZ_MOI = (
    "Divisions relevées dans les ouvrages eux-mêmes : un chapitre que "
    "l'extraction a laissé sans nom prend celui de la division où il commence, "
    "suivi de son rang quand la division en compte plusieurs. Clé : titre de "
    "l'ouvrage. Produit par pipeline/ingest/titrer.py, appliqué par "
    "corriger_corpus, qui garde l'original dans title_source."
)


def livre(nom: str):
    """Les noms de fichiers mêlent accents composés et combinés : on compare pliés."""
    cible = unicodedata.normalize("NFC", nom)
    for p in LIVRES.rglob("*.pdf"):
        if unicodedata.normalize("NFC", str(p.relative_to(LIVRES))) == cible:
            return pymupdf.open(p)
    raise SystemExit(f"Fichier introuvable dans livres/ : {nom}")


def plier(s: str) -> str:
    # L'apostrophe tombe à la conversion et colle les mots (« lAfrique ») : on
    # la remplace d'abord par une espace.
    s = s.replace("\u2019", " ").replace("'", " ")
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def lignes(doc, page: int, n: int = 6) -> list[str]:
    return [l.strip() for l in doc[page - 1].get_text("text").split("\n") if l.strip()][:n]


def ouvertures(doc, motif: re.Pattern, tete: int = 4) -> list[tuple[int, re.Match]]:
    """Les pages dont une des premières lignes porte le motif cherché."""
    trouvees = []
    for p in range(1, doc.page_count + 1):
        for l in lignes(doc, p, tete):
            m = motif.match(l)
            if m:
                trouvees.append((p, m))
                break
    return trouvees


def numero(brut: str) -> int:
    """« 1 1 », « 1 0 », « S » : la numérisation disloque les numéros de chapitre."""
    chiffres = brut.replace(" ", "").replace("S", "5").replace("O", "0").replace("l", "1")
    return int(chiffres)


def adosser(pages: dict[int, int], titres: dict[int, str], ouvrage: str) -> list[dict]:
    """Un intitulé relu par numéro, la page où il commence prise dans l'ouvrage."""
    manquants = sorted(set(titres) - set(pages))
    if manquants:
        raise SystemExit(f"{ouvrage} : divisions {manquants} introuvables dans le fichier.")
    inattendus = sorted(set(pages) - set(titres))
    if inattendus:
        raise SystemExit(f"{ouvrage} : divisions {inattendus} sans intitulé relu.")
    return [{"page": pages[n], "titre": titres[n]} for n in sorted(titres)]


# --------------------------------------------------------------- les ouvrages

PANORAMA_3 = {
    1: "Chapitre 1 : Informatique théorique, calculabilité, décidabilité et logique",
    2: "Chapitre 2 : Informatique théorique, complexité, automates et au-delà",
    3: "Chapitre 3 : Bases de données et intelligence artificielle",
    4: "Chapitre 4 : Web sémantique",
    5: "Chapitre 5 : Intelligence artificielle et langage",
    6: "Chapitre 6 : Bioinformatique",
    7: "Chapitre 7 : Intelligence artificielle et reconnaissance des formes, vision, apprentissage",
    8: "Chapitre 8 : Intelligence artificielle et robotique",
    9: "Chapitre 9 : Perspectives philosophiques et épistémologiques ouvertes par l'intelligence artificielle",
    10: "Chapitre 10 : Intelligence artificielle et psychologie du raisonnement et de la décision",
    11: "Chapitre 11 : Fertilisation croisée entre interaction personne-système et intelligence artificielle",
}

PANORAMA_2 = {
    1: "Chapitre 1 : Recherche heuristiquement ordonnée dans les graphes d'états",
    2: "Chapitre 2 : Jeux et recherche heuristique",
    3: "Chapitre 3 : Déduction automatique",
    4: "Chapitre 4 : Programmation logique",
    5: "Chapitre 5 : Logique propositionnelle et algorithmes autour de SAT",
    6: "Chapitre 6 : Raisonnement par contraintes",
    7: "Chapitre 7 : Réseaux de contraintes valués",
    8: "Chapitre 8 : Modèles graphiques pour l'incertitude, inférence et apprentissage",
    9: "Chapitre 9 : Planification en intelligence artificielle",
    10: "Chapitre 10 : Algorithmique de l'apprentissage et de la fouille de données",
    11: "Chapitre 11 : Méta-heuristiques et intelligence artificielle",
}

MANUEL = {
    1: "Chapitre 1 : Introduction",
    2: "Chapitre 2 : Énumération et complexité",
    3: "Chapitre 3 : Espace d'état et métaphore du labyrinthe",
    4: "Chapitre 4 : Méthodes de réduction",
    5: "Chapitre 5 : Réseaux sémantiques",
    6: "Chapitre 6 : Notions d'apprentissage",
    7: "Chapitre 7 : Bases du langage Scheme",
    8: "Chapitre 8 : Premières applications",
    9: "Chapitre 9 : Vers l'intelligence artificielle en Scheme",
    10: "Chapitre 10 : Calcul des propositions",
    11: "Chapitre 11 : Logique des prédicats",
    12: "Chapitre 12 : Éléments de Prolog",
    13: "Chapitre 13 : Compléments de programmation logique",
    14: "Chapitre 14 : Logiques multivaluées",
    15: "Chapitre 15 : Logiques floues",
    16: "Chapitre 16 : Logiques non monotones ou révisables",
    17: "Chapitre 17 : Logiques modales",
    18: "Chapitre 18 : Logiques d'ordre supérieur",
    19: "Chapitre 19 : Introduction aux systèmes experts",
    20: "Chapitre 20 : Systèmes experts, développement",
    21: "Chapitre 21 : Ingénierie et gestion des connaissances",
    22: "Chapitre 22 : Formalismes grammaticaux",
    23: "Chapitre 23 : Langages à classes",
    24: "Chapitre 24 : Langages à prototypes",
    25: "Chapitre 25 : Les acteurs",
    26: "Chapitre 26 : Agents et systèmes multi-agents",
    27: "Chapitre 27 : Les systèmes multi-agents",
    28: "Chapitre 28 : Métaconnaissances réactives et proactives",
    29: "Chapitre 29 : Traitement des langues naturelles",
    30: "Chapitre 30 : Autres systèmes intelligents spécialisés",
    31: "Chapitre 31 : Le projet robotique",
    32: "Chapitre 32 : Vie artificielle",
}

FOREST = {
    1: "Chapitre 1 : Management of forests and other natural resources",
    2: "Chapitre 2 : Valuing and characterizing forest conditions",
    3: "Chapitre 3 : Geographic information and land classification in support of forest planning",
    4: "Chapitre 4 : Estimation and projection of stand and forest conditions",
    5: "Chapitre 5 : Optimization of tree- and stand-level objectives",
    6: "Chapitre 6 : Graphical solution techniques for two-variable linear problems",
    7: "Chapitre 7 : Linear programming",
    8: "Chapitre 8 : Advanced planning techniques",
    9: "Chapitre 9 : Forest and natural resource sustainability",
    10: "Chapitre 10 : Models of desired forest structure",
    11: "Chapitre 11 : Control techniques for commodity production and wildlife objectives",
    12: "Chapitre 12 : Spatial restrictions and considerations in forest planning",
    13: "Chapitre 13 : Hierarchical system for planning and scheduling management activities",
    14: "Chapitre 14 : Forest supply chain management",
    15: "Chapitre 15 : Forest certification and carbon sequestration",
}

NKRUMAH = {
    1: "Chapitre 1 : Les ressources de l'Afrique",
    2: "Chapitre 2 : Les obstacles au progrès économique",
    3: "Chapitre 3 : La finance impérialiste",
    4: "Chapitre 4 : Le capitalisme de monopole et le dollar américain",
    5: "Chapitre 5 : La vérité sous les gros titres",
    6: "Chapitre 6 : Matières premières et intérêts étrangers",
    7: "Chapitre 7 : L'empire Oppenheimer",
    8: "Chapitre 8 : Investissements étrangers dans les mines d'Afrique du Sud",
    9: "Chapitre 9 : L'Anglo American Corporation Limited",
    10: "Chapitre 10 : Les groupes du diamant",
    11: "Chapitre 11 : Les intérêts miniers en Afrique centrale",
    12: "Chapitre 12 : Compagnies et combinats",
    13: "Chapitre 13 : Les géants de l'étain, de l'aluminium et du nickel",
    14: "Chapitre 14 : L'Union minière du Haut Katanga",
    15: "Chapitre 15 : Pressions économiques sur la République du Congo",
    16: "Chapitre 16 : Zones monétaires et banques étrangères",
    17: "Chapitre 17 : Les nouvelles industries et leurs effets sur les pays producteurs de matières premières",
    18: "Chapitre 18 : Les mécanismes du néo-colonialisme",
}

# Le titre que la numérisation a mal rendu sur la page d'ouverture du chapitre.
IA_THEORIQUE_RELUS = {
    1: "Définir l'intelligence artificielle",
    12: "Lambda-calcul",
    17: "Programmation fonctionnelle, ML",
    18: "Programmation logique, Prolog",
    14: "Problèmes de satisfaction de contraintes",
    19: "Apprentissage symbolique automatique",
}


def panorama(fichier: str, relus: dict[int, str], liminaires: list[dict], finales: list[dict]) -> list[dict]:
    doc = livre(fichier)
    pages = {numero(m.group(1)): p
             for p, m in ouvertures(doc, re.compile(r"^Chapitre\s+([\d ]{1,4})\s*$"))}
    return liminaires + adosser(pages, relus, fichier) + finales


def manuel() -> list[dict]:
    fichier = ("02-IA-Technique-Academique/"
               "Manuel dintelligence artificielle (Louis Frécon, Okba Kazar)@lechat.pdf")
    doc = livre(fichier)
    pages = {numero(m.group(1)): p
             for p, m in ouvertures(doc, re.compile(r"^CHAPITRE\s+([\dSOl ]{1,4})\s*$"))}
    return (
        [{"page": 7, "titre": "Avant-propos"},
         {"page": 9, "titre": "Plan de l'ouvrage"},
         {"page": 11, "titre": "Table des matières"}]
        + adosser(pages, MANUEL, fichier)
        + [{"page": 767, "titre": "Conclusion"}, {"page": 769, "titre": "Index"}]
    )


def ia_theorique() -> list[dict]:
    fichier = "02-IA-Technique-Academique/Intelligence_artificielle_et_informatique.ocr.pdf"
    doc = livre(fichier)
    titres, pages = {}, {}
    motif = re.compile(r"^CHAPITRE\s+(PREMIER|\d{1,2})\s*$")
    for p, m in ouvertures(doc, motif):
        n = 1 if m.group(1) == "PREMIER" else int(m.group(1))
        tete = lignes(doc, p, 6)
        # Le titre suit immédiatement la mention du chapitre, l'en-tête courant
        # de l'ouvrage ouvrant la page.
        apres = tete[tete.index(m.group(0)) + 1] if m.group(0) in tete else ""
        relu = IA_THEORIQUE_RELUS.get(n)
        pages[n] = p
        titres[n] = f"Chapitre {n} : {relu or apres[0].upper() + apres[1:]}"
    return (
        [{"page": 5, "titre": "Remerciements"},
         {"page": 7, "titre": "Table des matières"},
         {"page": 21, "titre": "Avant-propos"}]
        + adosser(pages, titres, fichier)
        + [{"page": 503, "titre": "Bibliographie"}, {"page": 535, "titre": "Index"}]
    )


def lois() -> list[dict]:
    """Les 48 intitulés sont au sommaire, les pages dans le corps du livre."""
    fichier = "09-Developpement-Personnel-Influence/les 48 lois du pouvoir .pdf"
    doc = livre(fichier)
    sommaire = "".join(doc[p - 1].get_text("text") for p in range(6, 14))
    titres, imprimees = {}, {}
    for m in re.finditer(r"LOI\s+(\d{1,2})\s*\npage\s+(\d+)\s*\n([^\n]+)", sommaire):
        n = int(m.group(1))
        intitule = m.group(3).strip().rstrip(".")
        titres[n] = f"Loi {n} : {intitule[0] + intitule[1:].lower()}"
        imprimees[n] = int(m.group(2))
    pages = {}
    for p in range(1, doc.page_count + 1):
        t = lignes(doc, p, 3)
        if len(t) > 2 and t[0] == "LOI" and re.fullmatch(r"\d{1,2}", t[1]):
            pages[int(t[1])] = p
    # Une loi dont la page d'ouverture est illisible : le décalage entre la
    # pagination imprimée et celle du fichier est constant, on s'en sert.
    decalages = {pages[n] - imprimees[n] for n in pages}
    if len(decalages) != 1:
        raise SystemExit(f"{fichier} : pagination irrégulière {sorted(decalages)}")
    for n in set(titres) - set(pages):
        pages[n] = imprimees[n] + decalages.pop() if decalages else 0
    # Les noms propres que la mise en minuscules effacerait.
    titres[31] = "Loi 31 : Offrez le choix, Charybde ou Scylla ?"
    titres[33] = "Loi 33 : Trouvez le talon d'Achille"
    return (
        [{"page": 4, "titre": "Remerciements"},
         {"page": 6, "titre": "Sommaire"},
         {"page": 14, "titre": "Préface"}]
        + adosser(pages, titres, fichier)
        + [{"page": 453, "titre": "Sources"}, {"page": 456, "titre": "Index"}]
    )


def forest() -> list[dict]:
    fichier = "11-Sciences-Environnement/Forest Management and Planning-1.pdf"
    doc = livre(fichier)
    pages = {}
    for p in range(1, doc.page_count + 1):
        t = lignes(doc, p, 3)
        if t and t[0].startswith("C H A P T E R") and re.fullmatch(r"\d{1,2}", t[1]):
            pages[int(t[1])] = p
    return (
        [{"page": 6, "titre": "Contents"}, {"page": 10, "titre": "Preface"}]
        + adosser(pages, FOREST, fichier)
        + [{"page": 308, "titre": "Annexe A : databases used throughout the book"},
           {"page": 326, "titre": "Annexe B : the simplex method for solving linear problems"},
           {"page": 334, "titre": "Annexe C : writing a memorandum or report"},
           {"page": 338, "titre": "Index"}]
    )


def nkrumah() -> list[dict]:
    fichier = "07-Afrique-Histoire-Pensee/Kwame_Nkrumah,_le_néo_colonialisme,_dernier_stade_de_l'impérialisme.pdf"
    doc = livre(fichier)
    # La numérisation abîme les numéros de chapitre (« o. » pour 5) : on
    # reconnaît chaque ouverture à son intitulé, relevé dans la table des matières.
    pages = {}
    for p in range(1, doc.page_count + 1):
        tete = plier(" ".join(lignes(doc, p, 6)))
        for n, titre in NKRUMAH.items():
            if n in pages:
                continue
            attendu = plier(titre.split(" : ", 1)[1])[:22]
            if attendu in tete[:len(attendu) + 6]:
                pages[n] = p
    return (
        [{"page": 9, "titre": "Dédicace"}, {"page": 11, "titre": "Introduction"}]
        + adosser(pages, NKRUMAH, fichier)
        + [{"page": 263, "titre": "Conclusion"},
           {"page": 268, "titre": "Bibliographie"},
           {"page": 271, "titre": "Table des matières"}]
    )


OUVRAGES = {
    "Panorama de l'intelligence artificielle. Volume 3 : l'intelligence artificielle, frontières et applications":
        lambda: panorama(
            "02-IA-Technique-Academique/Panorama de lIntelligence Artificielle - Ses bases "
            "méthodologiques, ses développements - Volume 3, Lintelligence artificielle... "
            "(Pierre MARQUIS, Odile PAPINI etc.) @lechat.pdf",
            PANORAMA_3,
            [{"page": 5, "titre": "Présentation de l'ouvrage"},
             {"page": 7, "titre": "Sommaire des trois volumes"},
             {"page": 15, "titre": "Préface"}],
            [{"page": 339, "titre": "Postface : la machine en quête de sapience"},
             {"page": 349, "titre": "Épilogue : pour une défense de la recherche en intelligence artificielle"},
             {"page": 361, "titre": "Index"}],
        ),
    "Panorama de l'intelligence artificielle. Volume 2 : algorithmes pour l'intelligence artificielle":
        lambda: panorama(
            "02-IA-Technique-Academique/Panorama de lIntelligence Artificielle - Ses bases "
            "méthodologiques, ses développements - Volume 2, Algorithmes pour... "
            "(Pierre Marquis, Odile Papini etc.) @lechat.pdf",
            PANORAMA_2,
            [{"page": 5, "titre": "Présentation de l'ouvrage"},
             {"page": 7, "titre": "Avant-propos des trois volumes"},
             {"page": 11, "titre": "Liste des auteurs du volume"},
             {"page": 13, "titre": "Préface"}],
            [{"page": 343, "titre": "Postface : intelligence artificielle et recherche opérationnelle"},
             {"page": 351, "titre": "Index"},
             {"page": 363, "titre": "Table des matières"}],
        ),
    "Manuel d'intelligence artificielle": manuel,
    "Intelligence artificielle et informatique théorique": ia_theorique,
    "Les 48 lois du pouvoir": lois,
    "Forest Management and Planning. Aménagement et planification forestiers": forest,
    "Le néo-colonialisme, dernier stade de l'impérialisme": nkrumah,
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--plan", action="store_true", help="montrer sans écrire")
    a = ap.parse_args()

    releve = {"_lisez-moi": LISEZ_MOI}
    for ouvrage, construire in OUVRAGES.items():
        divisions = construire()
        pages = [d["page"] for d in divisions]
        if pages != sorted(set(pages)):
            raise SystemExit(f"{ouvrage} : pages en désordre ou en doublon.")
        releve[ouvrage] = divisions
        print(f"{ouvrage[:62]:62} {len(divisions):>3} divisions, pages {pages[0]} à {pages[-1]}")
        if a.plan:
            for d in divisions:
                print(f"    p{d['page']:>4}  {d['titre']}")

    if a.plan:
        print("\nMode plan : rien n'a été écrit.")
        return
    SORTIE.write_text(json.dumps(releve, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\n{SORTIE.relative_to(Path(__file__).resolve().parents[2])} : "
          f"{sum(len(v) for k, v in releve.items() if k != '_lisez-moi')} divisions.")


if __name__ == "__main__":
    main()
