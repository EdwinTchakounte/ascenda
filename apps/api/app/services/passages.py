"""Le texte des passages, tel qu'un lecteur doit le lire.

L'ingestion découpe chaque livre en passages d'environ 750 jetons qui se
chevauchent : chaque passage reprend les 330 derniers caractères du précédent,
coupés au caractère près. Ce recouvrement sert la recherche (une idée à cheval
sur deux passages reste trouvable), mais affiché tel quel il produit trois
défauts visibles :

- un chapitre commence par la fin du chapitre précédent, au milieu d'un mot
  (« ère Les textes générés par l'IA… ») ;
- entre deux passages, une phrase entière apparaît deux fois ;
- le texte garde les retours à la ligne de la mise en page du PDF, et les mots
  coupés en fin de ligne (« amé-\\nnagement »).

On ne réingère pas le corpus pour autant : les vecteurs, les quiz et les
citations sont rattachés aux passages existants. On corrige à l'affichage, avec
le passage précédent sous la main.
"""
import re

_DEBUT_FRAGMENT = re.compile(r"^[a-zà-ÿ’']")


def sans_reprise(precedent: str | None, texte: str) -> str:
    """Retire du début de `texte` ce qui répète la fin de `precedent`.

    L'ingestion recopie la fin du passage précédent en tête du suivant : on
    cherche donc cette fin au tout début du passage, de la plus longue à la plus
    courte.
    """
    if not precedent:
        return texte
    fin = precedent.rstrip()
    for k in range(min(len(fin), 700), 14, -1):
        reprise = fin[-k:].lstrip()
        if len(reprise) >= 15 and texte.startswith(reprise):
            return texte[len(reprise):].lstrip()
    # Sans reprise reconnue, on ne coupe rien : un début en minuscule est bien
    # plus souvent la suite d'une phrase, d'une page à l'autre, qu'un fragment.
    return texte


_FIN_PHRASE = re.compile(r"[.!?:;»\")\]…]$")
_DEBUT_BLOC = re.compile(r"^([-•–—*]|\d+[.)]|[A-ZÀ-Ý])")


def replier(texte: str) -> str:
    """Recolle les lignes que la mise en page du PDF a coupées.

    Une ligne qui ne finit pas une phrase se prolonge sur la suivante ; un mot
    coupé par un trait d'union en fin de ligne est recollé. Les paragraphes
    (ligne vide) et les lignes qui finissent une phrase avant une majuscule ou une
    puce restent des retours à la ligne.
    """
    # Les numéros de page imprimés (« – 161 – ») ne sont pas du texte à lire.
    lignes = [l.strip() for l in texte.replace("\r", "").split("\n")
              if not re.fullmatch(r"[-–—]?\s*\d{1,4}\s*[-–—]?", l.strip()) or not l.strip()]
    sortie: list[str] = []
    for ligne in lignes:
        if not ligne:
            if sortie and sortie[-1] != "":
                sortie.append("")
            continue
        if not sortie or sortie[-1] == "":
            sortie.append(ligne)
            continue
        precedente = sortie[-1]
        if re.search(r"[a-zà-ÿ]-$", precedente) and re.match(r"[a-zà-ÿ]", ligne):
            sortie[-1] = precedente[:-1] + ligne
        elif _FIN_PHRASE.search(precedente) and _DEBUT_BLOC.match(ligne):
            sortie.append(ligne)
        elif len(precedente) < 45 and _DEBUT_BLOC.match(ligne) and not precedente.endswith(","):
            # Une ligne courte suivie d'une majuscule : un titre ou une entrée
            # de liste, qu'on ne fond pas dans le paragraphe suivant.
            sortie.append(ligne)
        else:
            sortie[-1] = f"{precedente} {ligne}"
    return "\n".join(sortie).strip()


_MOTS_ALLEMANDS = {"der", "die", "und", "das", "ist", "nicht", "mit", "ein", "eine", "für", "auf", "sich",
                   "den", "zu", "auch", "dem", "wird", "werden", "sind", "von"}
_MOTS_FRANCAIS = {"le", "la", "les", "des", "et", "est", "une", "dans", "que", "pour", "qui", "pas", "sur",
                  "avec", "par", "du", "au", "ce", "il", "sont"}


def sans_reste_etranger(texte: str) -> str:
    """Retire les paragraphes restés dans la langue d'origine d'un livre traduit.

    Deux passages du corpus portent un paragraphe allemand au milieu du texte
    français, oubli de la traduction du fichier source. On ne le montre pas : un
    lecteur le prendrait pour une erreur d'affichage.
    """
    gardes = []
    for paragraphe in texte.split("\n"):
        mots = re.findall(r"[a-zäöüßéèàçâêîôûœ]+", paragraphe.lower())
        allemand = sum(m in _MOTS_ALLEMANDS for m in mots)
        francais = sum(m in _MOTS_FRANCAIS for m in mots)
        if allemand >= 5 and allemand > francais:
            continue
        gardes.append(paragraphe)
    return "\n".join(gardes).strip()


def lisibles(textes: list[str], precedent: str | None = None) -> list[str]:
    """Une suite de passages consécutifs, sans reprise et recollés."""
    sortie = []
    avant = precedent
    for t in textes:
        propre = sans_reprise(avant, t)
        avant = t
        sortie.append(sans_reste_etranger(replier(propre)))
    return sortie


def extrait(texte: str) -> str:
    """Un passage isolé (résultat de recherche, source de l'agent), recollé.

    Sans le passage précédent, on ne sait pas retirer la reprise ; on signale
    seulement par « … » un début qui tombe au milieu d'une phrase.
    """
    t = replier(texte)
    return f"…{t}" if _DEBUT_FRAGMENT.match(t) else t
