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


def fichier_livre(nom: str):
    """Les noms de fichiers mêlent accents composés et combinés : on compare pliés."""
    cible = unicodedata.normalize("NFC", nom)
    for p in LIVRES.rglob("*.*"):
        if unicodedata.normalize("NFC", str(p.relative_to(LIVRES))) == cible:
            return p
    raise SystemExit(f"Fichier introuvable dans livres/ : {nom}")


def livre(nom: str):
    return pymupdf.open(fichier_livre(nom))


def plier(s: str) -> str:
    # L'apostrophe tombe à la conversion et colle les mots (« lAfrique ») : on
    # la remplace d'abord par une espace.
    s = s.replace("\u2019", " ").replace("'", " ")
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def lignes(doc, page: int, n: int = 6) -> list[str]:
    return [l.strip() for l in doc[page - 1].get_text("text").split("\n") if l.strip()][:n]


SOMMAIRE = re.compile(r"\.{6,}")


def ouvertures(doc, motif: re.Pattern, tete: int = 4) -> list[tuple[int, re.Match]]:
    """Les pages dont une des premières lignes porte le motif cherché.

    Une page de sommaire, reconnaissable à ses lignes de points de conduite,
    reprend les mêmes mentions sans ouvrir quoi que ce soit.
    """
    trouvees = []
    for p in range(1, doc.page_count + 1):
        if len(SOMMAIRE.findall(doc[p - 1].get_text("text"))) >= 3:
            continue
        for l in lignes(doc, p, tete):
            m = motif.match(l)
            if m:
                trouvees.append((p, m))
                break
    return trouvees


def textes_epub(nom: str) -> list[str]:
    """Les pages d'un epub telles que l'ingestion les compte : un document par
    page, ceux qui ne portent presque rien étant écartés."""
    import warnings
    warnings.filterwarnings("ignore")
    from bs4 import BeautifulSoup
    from ebooklib import ITEM_DOCUMENT, epub

    from common import norm
    chemin = fichier_livre(nom)
    pages = []
    for item in epub.read_epub(str(chemin), options={"ignore_ncx": True}).get_items():
        if item.get_type() != ITEM_DOCUMENT:
            continue
        txt = norm(BeautifulSoup(item.get_content(), "lxml").get_text("\n"))
        if len(txt.strip()) >= 40:
            pages.append(txt)
    return pages


def controler(pages, divisions: list[dict], ouvrage: str) -> list[dict]:
    """Une division relevée à la main doit se retrouver sur la page annoncée."""
    for d in divisions:
        intitule = d["titre"].split(" : ", 1)[-1]
        mots = [plier(m) for m in re.findall(r"[^\W\d_]{7,}", intitule, re.UNICODE)]
        if not mots or not (1 <= d["page"] <= len(pages)):
            if not (1 <= d["page"] <= len(pages)):
                raise SystemExit(f"{ouvrage} : page {d['page']} hors du fichier ({len(pages)} pages).")
            continue
        texte = plier(pages[d["page"] - 1][:2500])
        if not any(m in texte for m in mots):
            raise SystemExit(f"{ouvrage} : « {d['titre']} » ne se retrouve pas page {d['page']}.")
    return divisions


def premieres_pages(doc, motif: re.Pattern, convertir=None, tete: int = 4) -> dict[int, int]:
    """La première page où chaque division s'ouvre. La table des matières, plus
    loin dans l'ouvrage, reprend les mêmes mentions : elle ne compte pas."""
    pages: dict[int, int] = {}
    for p, m in ouvertures(doc, motif, tete=tete):
        n = convertir(m) if convertir else numero(m.group(1))
        if n and n not in pages:
            pages[n] = p
    return pages


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
    pages = premieres_pages(doc, re.compile(r"^Chapitre\s+([\d ]{1,4})\s*$"))
    return liminaires + adosser(pages, relus, fichier) + finales


def manuel() -> list[dict]:
    fichier = ("02-IA-Technique-Academique/"
               "Manuel dintelligence artificielle (Louis Frécon, Okba Kazar)@lechat.pdf")
    doc = livre(fichier)
    pages = premieres_pages(doc, re.compile(r"^CHAPITRE\s+([\dSOl ]{1,4})\s*$"))
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


PENSEE_POLITIQUE = {
    1: "Chapitre 1 : L'œuvre de Cheikh Anta Diop face à l'épreuve de la postérité",
    2: "Chapitre 2 : Les racines contextuelles de la pensée politique de Cheikh Anta Diop",
    3: "Chapitre 3 : Les assises scientifiques de la pensée politique de Cheikh Anta Diop",
    4: "Chapitre 4 : Les directives politiques de Cheikh Anta Diop",
}

# Les deux éditions du même livre. La retraduction automatique rend les titres
# en anglais calqué (« FORMATION DU MODERNE ÉTATS EUROPÉENS ») : on reprend
# ceux de l'édition française.
PRECOLONIALE = {
    1: "Chapitre I : Analyse de la notion de caste",
    2: "Chapitre II : Évolution politico-sociale de la cité antique",
    3: "Chapitre III : Formation des États modernes européens",
    4: "Chapitre IV : Organisation politique en Afrique noire",
    5: "Chapitre V : Organisation étatique, puissance des empires africains",
    6: "Chapitre VI : Organisation économique",
    7: "Chapitre VII : Superstructure idéologique, l'islam en Afrique noire",
    8: "Chapitre VIII : Niveau intellectuel, enseignement et éducation",
    9: "Chapitre IX : Niveau technique",
    10: "Chapitre X : Migration et formation des peuples actuels de l'Afrique",
    11: "Chapitre XI : Appendice linguistique",
}

KUNTA = {
    1: "Première partie : je suis Kunta Kinte",
    2: "Deuxième partie : je suis conscient du combat",
    3: "Troisième partie : je dois acheter ma liberté",
    4: "Quatrième partie : je consomme de façon intelligente",
    5: "Cinquième partie : je crée d'autres sources",
    6: "Sixième partie : je deviens maître",
    7: "Septième partie : je prépare Kizzy",
    8: "Huitième partie : l'état d'esprit fait la différence",
    9: "Neuvième partie : je refuse d'être un mouton de Panurge",
    10: "Dixième partie : je dois continuer d'aller de l'avant",
    11: "Onzième partie : la puissance d'une idée positive",
}

ORDINAUX = ["PREMIÈRE", "DEUXIÈME", "TROISIÈME", "QUATRIÈME", "CINQUIÈME", "SIXIÈME",
            "SEPTIÈME", "HUITIÈME", "NEUVIÈME", "DIXIÈME", "ONZIÈME"]

# Les idées reçues que l'ouvrage examine, dans l'ordre, avec la page où chacune
# s'ouvre. La numérisation abîme les guillemets et coupe les mots : les
# intitulés sont relus, les pages contrôlées sur le texte de la page.
GANASCIA = [
    (19, "Alan Turing est l'inventeur de l'intelligence artificielle"),
    (25, "Désormais des machines passent le test de Turing"),
    (31, "L'intelligence artificielle n'est pas une science"),
    (37, "L'intelligence artificielle est une idée neuve"),
    (43, "Les Japonais sont les champions de l'intelligence artificielle"),
    (49, "La recherche en intelligence artificielle est menée par les GAFA"),
    (55, "L'intelligence artificielle pallie les défaillances de notre intelligence"),
    (59, "Nous passerons bientôt de l'intelligence artificielle faible à la forte"),
    (69, "Il n'y a rien à craindre avec les ordinateurs, il suffit de les débrancher"),
    (75, "L'intelligence artificielle reproduit l'activité de notre cerveau"),
    (81, "L'intelligence artificielle n'est pas naturelle"),
    (85, "Les ordinateurs raisonnent de façon binaire"),
    (89, "Les ordinateurs ne se trompent jamais"),
    (93, "Les ordinateurs sont invincibles aux échecs et au go"),
    (101, "Le « deep learning » révolutionne l'intelligence artificielle"),
    (109, "Une machine ne peut pas être créative"),
    (117, "Les machines n'ont pas d'émotions ni de conscience"),
    (123, "Les machines n'ont pas d'intuition"),
    (129, "Nous confierons bientôt les personnes âgées aux robots"),
    (133, "Les voitures autonomes sont programmées pour tuer leurs passagers"),
    (137, "Le « big data » menace la démocratie"),
    (143, "Les « robots tueurs » remplaceront bientôt les soldats"),
    (151, "Il faut donner des droits aux robots"),
    (159, "Nous ne sommes pas prêts pour le tsunami technologique qui advient"),
    (163, "L'intelligence artificielle n'a pas tenu ses promesses"),
    (169, "Les robots nous mettront tous au chômage"),
    (175, "Demain, nous serons les esclaves des machines"),
    (181, "Il n'y a plus de débouchés professionnels en intelligence artificielle"),
    (187, "L'intelligence artificielle constitue un danger existentiel pour l'humanité"),
    (193, "Grâce à l'intelligence artificielle, nous deviendrons immortels"),
    (199, "La machine est l'avenir de l'homme"),
]


def pensee_politique() -> list[dict]:
    fichier = "07-Afrique-Histoire-Pensee/la pensée politique de Cheikh Anta Diop.pdf"
    doc = livre(fichier)
    pages = premieres_pages(doc, re.compile(r"^CHAPITRE\s+([\d ]{1,3})\s*$"))
    return (
        [{"page": 7, "titre": "Introduction"}]
        + adosser(pages, PENSEE_POLITIQUE, fichier)
        + [{"page": 179, "titre": "Conclusion"},
           {"page": 183, "titre": "Bibliographie"},
           {"page": 189, "titre": "Table des matières"}]
    )


def precoloniale_francaise() -> list[dict]:
    fichier = "07-Afrique-Histoire-Pensee/LAfrique noire pré-coloniale (Cheikh Anta Diop).pdf"
    doc = livre(fichier)
    romains = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7, "Vil": 7,
               "VIII": 8, "IX": 9, "X": 10, "XI": 11}
    pages = premieres_pages(doc, re.compile(r"^CHAPITRE\s+([IVXil]{1,5})\s*$"),
                            lambda m: romains.get(m.group(1)))
    return (
        [{"page": 15, "titre": "Préface"}]
        + adosser(pages, PRECOLONIALE, fichier)
        + [{"page": 224, "titre": "Bibliographie"},
           {"page": 227, "titre": "Table des matières"}]
    )


def precoloniale_retraduite() -> list[dict]:
    fichier = "07-Afrique-Histoire-Pensee/Afrique noire précoloniale Une étude Cheikh Anta Diop.pdf"
    doc = livre(fichier)
    lettres = {"un": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6,
               "sept": 7, "huit": 8, "neuf": 9, "dix": 10, "x": 10}
    pages = premieres_pages(doc, re.compile(r"^Chapitre\s+([A-Za-z]{1,7})\s*$"),
                            lambda m: lettres.get(m.group(1).lower()))
    titres = {n: t for n, t in PRECOLONIALE.items() if n <= 10}
    return (
        [{"page": 5, "titre": "Table des matières"},
         {"page": 9, "titre": "Préface"},
         {"page": 11, "titre": "Pages liminaires reprises par la numérisation"}]
        + adosser(pages, titres, fichier)
        + [{"page": 263, "titre": "Bibliographie"}]
    )


def kunta() -> list[dict]:
    fichier = "07-Afrique-Histoire-Pensee/Je suis KUNTA - Ricardo Kaniama-1.pdf"
    doc = livre(fichier)
    pages = premieres_pages(doc, re.compile(r"^(" + "|".join(ORDINAUX) + r") PARTIE\b"),
                            lambda m: ORDINAUX.index(m.group(1)) + 1, tete=2)
    return (
        [{"page": 12, "titre": "Introduction"}]
        + adosser(pages, KUNTA, fichier)
        + [{"page": 141, "titre": "Ainsi parla Kunta Kinte"},
           {"page": 145, "titre": "Que son message vous parle aussi"},
           {"page": 153, "titre": "Après la lecture"}]
    )


def ganascia() -> list[dict]:
    fichier = ("04-IA-Societe-Ethique-Philosophie/"
               "Intelligence artificielle - Jean-Gabriel GANASCIA (1).ocr.pdf")
    doc = livre(fichier)
    idees = [{"page": p, "titre": f"Idée reçue {i} : « {t}. »"}
             for i, (p, t) in enumerate(GANASCIA, 1)]
    # Les pages liminaires et les annexes n'ont pas d'intitulé sur leur première
    # page, seul l'en-tête courant des pages suivantes le porte : rien à contrôler.
    return (
        [{"page": 7, "titre": "Sommaire"}, {"page": 11, "titre": "Introduction"}]
        + controler([doc[i].get_text("text") for i in range(doc.page_count)], idees, fichier)
        + [{"page": 203, "titre": "Conclusion"},
           {"page": 209, "titre": "Glossaire"},
           {"page": 213, "titre": "Pour aller plus loin"}]
    )


def brochure_education() -> list[dict]:
    fichier = "05-IA-Education-Pedagogie/MEN_DNE_brochure_IA_WEB.pdf"
    doc = livre(fichier)
    divisions = [
        {"page": 3, "titre": "Table des matières"},
        {"page": 4, "titre": "Résumé"},
        {"page": 6, "titre": "1. L'intelligence artificielle, une diversité de définitions"},
        {"page": 11, "titre": "2. Quels enjeux pour les politiques publiques ?"},
        {"page": 17, "titre": "3. Quels enjeux éthiques ?"},
        {"page": 19, "titre": "4. Quels domaines d'application ?"},
        {"page": 23, "titre": "5. Quelles pistes de travail pour former à l'intelligence artificielle ?"},
        {"page": 26, "titre": "6. Le tournant des IA génératives et des grands modèles de langage"},
        {"page": 35, "titre": "Références"},
    ]
    return controler([doc[i].get_text("text") for i in range(doc.page_count)], divisions, fichier)


def religion_africaine() -> list[dict]:
    fichier = ("07-Afrique-Histoire-Pensee/"
               "CHEIKH_ANTA_DIOP_ET_L’HISTOIRE_DE_LA_RELIGION_AFRICAINE_1.pdf")
    doc = livre(fichier)
    divisions = [
        {"page": 2, "titre": "Introduction"},
        {"page": 3, "titre": "I. La fondation de l'histoire moderne de la religion africaine"},
        {"page": 5, "titre": "II. La méthodologie de l'étude"},
        {"page": 6, "titre": "III. La description de la cosmogonie africaine de l'Antiquité"},
        {"page": 9, "titre": "IV. L'apport conceptuel africain aux religions révélées"},
        {"page": 15, "titre": "V. La portée de la thèse de l'origine cosmo-théologique"},
    ]
    return (controler([doc[i].get_text("text") for i in range(doc.page_count)], divisions, fichier)
            + [{"page": 23, "titre": "Notes et références"}])


def ia_demystifiee() -> list[dict]:
    # Les titres de cet ouvrage sont dessinés : le texte extrait colle les mots
    # (« IAETGENAI: LESBASES »), aucun contrôle automatique n'y mord.
    return [
        {"page": 2, "titre": "Sommaire"},
        {"page": 4, "titre": "Avertissement"},
        {"page": 5, "titre": "Quiz de découverte"},
        {"page": 6, "titre": "Introduction"},
        {"page": 9, "titre": "IA et IA générative, les bases"},
        {"page": 15, "titre": "Outils d'intelligence artificielle essentiels"},
        {"page": 27, "titre": "Prompts et cas pratiques"},
        {"page": 38, "titre": "Stratégies et astuces"},
        {"page": 43, "titre": "Conclusion, passez à l'action"},
    ]


def notre_chateau() -> list[dict]:
    """Le roman est en trois parties, dont les pages de titre ne portent qu'un
    numéro : l'ingestion les écarte, et les sections qui suivent se numérotent
    de 1 à 10 dans chaque partie. On nomme donc les parties, pas les sections."""
    fichier = "08-Litterature-Romans/Regniez Emmanuel - Notre château @EpubsFR.epub"
    pages = textes_epub(fichier)
    if len(pages) != 40:
        raise SystemExit(f"{fichier} : {len(pages)} pages lues, 40 attendues.")
    return [
        {"page": 1, "titre": "Pages liminaires"},
        {"page": 5, "titre": "Partie I"},
        {"page": 15, "titre": "Partie II"},
        {"page": 25, "titre": "Partie III"},
        {"page": 38, "titre": "Pages finales"},
    ]


def meditations() -> list[dict]:
    """Chaque méditation tient une page et s'ouvre sur son titre. Les pages de
    journal n'en ont pas : leur première phrase en tient lieu."""
    fichier = "07-Afrique-Histoire-Pensee/Méditations africaines by Sarr Felwine (z-lib.org).epub"
    pages = textes_epub(fichier)
    if len(pages) != 25:
        raise SystemExit(f"{fichier} : {len(pages)} pages lues, 25 attendues.")
    divisions = [{"page": 1, "titre": "Mentions d'édition"},
                 {"page": 2, "titre": "Page de titre"},
                 {"page": 3, "titre": "Du même auteur"}]
    for n in range(4, 26):
        tete = next(l.strip() for l in pages[n - 1].split("\n") if l.strip())
        divisions.append({"page": n, "titre": tete if len(tete) <= 70 else tete[:69].rstrip(" ,;:") + "…"})
    return divisions


def par_tetes(fichier: str, pages: range, liminaires: list[dict] | None = None) -> list[dict]:
    """Un support de formation : chaque page porte son titre sur sa première ligne."""
    doc = livre(fichier)
    divisions = list(liminaires or [])
    for n in pages:
        # Un titre de diapositive tient souvent sur deux ou trois lignes.
        tete = ""
        for l in lignes(doc, n, 3):
            tete = (tete + " " + l).strip()
            if len(tete) >= 25:
                break
        if not tete:
            continue
        divisions.append({"page": n, "titre": tete if len(tete) <= 70 else tete[:69].rstrip(" ,;:") + "…"})
    return divisions


def money_management() -> list[dict]:
    return [
        {"page": 3, "titre": "1. Généralités et principes de base"},
        {"page": 24, "titre": "2. Les stratégies de money-management"},
        {"page": 42, "titre": "3. Établir un plan de trading"},
        {"page": 48, "titre": "4. L'état d'esprit gagnant"},
    ]


def ia_tourisme() -> list[dict]:
    return [
        {"page": 1, "titre": "Ouverture et objectifs"},
        {"page": 8, "titre": "Introduction"},
        {"page": 16, "titre": "L'intelligence artificielle générative"},
        {"page": 23, "titre": "Les prompts"},
        {"page": 38, "titre": "Utiliser l'IA pour le web"},
        {"page": 42, "titre": "Utiliser l'IA pour ses réseaux sociaux"},
        {"page": 49, "titre": "Utiliser l'IA pour gérer sa e-réputation"},
        {"page": 54, "titre": "Utiliser l'IA pour améliorer ses ventes en ligne"},
        {"page": 61, "titre": "Utiliser l'IA pour améliorer sa visibilité locale"},
    ]


def cours_robotique() -> list[dict]:
    return [
        {"page": 1, "titre": "Présentation du module"},
        {"page": 11, "titre": "Première partie : introduction à l'intelligence artificielle"},
    ]


def modelisation_risque() -> list[dict]:
    return [
        {"page": 3, "titre": "Sommaire"},
        {"page": 4, "titre": "Introduction générale"},
        {"page": 5, "titre": "Partie 1 : les soubassements théoriques de la modélisation du risque"},
        {"page": 6, "titre": "Chapitre 1 : soubassements théoriques et démarche méthodologique"},
    ]


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
    "La pensée politique de Cheikh Anta Diop": pensee_politique,
    "L'Afrique noire pré-coloniale. Étude comparée des systèmes politiques et sociaux de l'Europe "
    "et de l'Afrique noire, de l'Antiquité à la formation des États modernes": precoloniale_francaise,
    "L'Afrique noire précoloniale (retraduction automatique de l'édition américaine)": precoloniale_retraduite,
    "Je suis Kunta Kinte. Pourquoi vous devez vous battre pour devenir riche": kunta,
    "Intelligence artificielle : vers une domination programmée ?": ganascia,
    "Intelligence artificielle et éducation. Apports de la recherche et enjeux "
    "pour les politiques publiques": brochure_education,
    "Cheikh Anta Diop et l'histoire de la religion africaine : les sources cosmo-théologiques "
    "philosophiques africaines des religions révélées": religion_africaine,
    "L'IA démystifiée. Guide des premiers pas": ia_demystifiee,
    "Notre Château": notre_chateau,
    "Méditations africaines": meditations,
    "Le money management. Support de formation au trading, chapitre 6": money_management,
    "Utiliser l'intelligence artificielle pour gagner du temps dans la gestion "
    "de son marketing numérique": ia_tourisme,
    "Enseigner avec l'IA à l'ère de la digitalisation des enseignements":
        lambda: par_tetes("05-IA-Education-Pedagogie/Enseigner avec IA-CIESD.pdf", range(2, 19)),
    "Introduction à l'intelligence artificielle et la robotique (support de cours)": cours_robotique,
    "Intelligence artificielle et modélisation du risque de crédit (extrait promotionnel)":
        modelisation_risque,
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
