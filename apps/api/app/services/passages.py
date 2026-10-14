"""Le texte des passages, tel qu'un lecteur doit le lire."""
import re

_DEBUT_FRAGMENT = re.compile(r"^[a-zà-ÿ’']")


def sans_reprise(precedent: str | None, texte: str) -> str:
    """Retire du début de `texte` ce qui répète la fin de `precedent`."""
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
    """Recolle les lignes que la mise en page du PDF a coupées."""
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
    """Retire les paragraphes restés dans la langue d'origine d'un livre traduit."""
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
    """Un passage isolé (résultat de recherche, source de l'agent), recollé."""
    t = replier(texte)
    return f"…{t}" if _DEBUT_FRAGMENT.match(t) else t
