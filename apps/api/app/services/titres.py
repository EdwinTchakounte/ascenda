"""Les titres de chapitre, tels qu'un lecteur doit pouvoir les lire.

Le découpage en chapitres vient de l'extraction des PDF. Quand un livre n'a pas
de table des matières exploitable, le pipeline nomme ses parties par leurs pages
(« Pages 66 à 197 ») : c'est un repli honnête. Mais l'extraction laisse aussi
passer de vrais défauts, qu'un lecteur prend pour des erreurs d'ASCENDA :

- un numéro de page pris pour un titre (« -7- ») ;
- un bandeau de mise en page (« suite de la page précédente », « chapitre ») ;
- un titre coupé en plein mot à la fin d'une ligne (« …de l'in- ») ;
- un séparateur resté en fin de titre (« BIOGRAPHIE - DAVID GRUSON - »).

Ce module les reconnaît et propose un titre lisible. La correction elle-même est
écrite en base par `app.outils.corriger_chapitres`, qui garde l'original.
"""
import re
import unicodedata

_REPLI = re.compile(r"^Pages? \d+( à \d+)?$")
_NUMERO = re.compile(r"^\s*[-–—]?\s*\d{1,4}\s*[-–—]?\s*$")
_BANDEAUX = {
    "suite de la page precedente", "suite", "chapitre", "chapter", "partie", "sans titre", "untitled",
}
_APPAREIL = {
    "couverture", "copyright", "page de copyright", "page de titre", "titre", "sommaire",
    "table des matieres", "index", "dedicace", "remerciements", "quatrieme de couverture",
    "du meme auteur", "mentions legales", "colophon", "acheve d'imprimer", "acheve d imprimer",
    "bibliographie", "biographie", "les auteurs", "a propos de l'auteur", "a propos des auteurs",
    "l'auteur", "des memes auteurs", "table", "sources", "credits", "credits photographiques",
}
# Un nom de fichier ou une étiquette de numérisation pris pour un titre :
# « PIA3_Страница_177_1L ».
_NOM_FICHIER = re.compile(r"\w+_\w+_\d|[\u0400-\u04FF\u0590-\u05FF]")
_MOT_COUPE = re.compile(r"[A-Za-zÀ-ÿ’']-$")
_SEPARATEUR_FINAL = re.compile(r"\s+[-–—]\s*$")


def _net(titre: str | None) -> str:
    t = unicodedata.normalize("NFKD", (titre or "").strip()).encode("ascii", "ignore").decode()
    return re.sub(r"\s+", " ", t.replace("’", "'")).strip(" .:").lower()


def est_repli(titre: str | None) -> bool:
    return bool(titre) and bool(_REPLI.match(titre.strip()))


def est_appareil(titre: str | None) -> bool:
    """Couverture, copyright, sommaire : des pages qu'on ne programme pas en séance."""
    return _net(titre) in _APPAREIL


def est_titre_casse(titre: str | None) -> bool:
    if titre is None or not titre.strip():
        return True
    t = titre.strip()
    return (
        bool(_NUMERO.match(t))
        or _net(t) in _BANDEAUX
        or bool(_MOT_COUPE.search(t))
        or bool(_SEPARATEUR_FINAL.search(t))
        or bool(_NOM_FICHIER.search(t))
    )


def completer_mot_coupe(titre: str, texte: str | None) -> str | None:
    """Retrouve la fin d'un titre coupé dans le texte du chapitre.

    « Que pouvons-nous attendre du développement de l'in- » se lit en entier
    dans les premières lignes du chapitre, où la coupure n'est qu'un retour à la
    ligne. On cherche le début du titre et on prend la suite jusqu'à la fin du
    mot. Sans correspondance sûre, on ne devine rien.
    """
    if not texte:
        return None
    debut = titre.rstrip("-").strip()
    if len(debut) < 12:
        return None
    # Le texte peut porter le tiret de coupure suivi d'un saut de ligne, ou le
    # mot entier : on accepte les deux.
    motif = re.escape(debut).replace(r"\ ", r"\s+") + r"-?\s*([A-Za-zÀ-ÿ’']+)"
    m = re.search(motif, texte, flags=re.IGNORECASE)
    if not m:
        return None
    return f"{debut}{m.group(1)}"


def titre_lisible(
    titre: str | None,
    *,
    page_start: int | None,
    page_end: int | None,
    precedent: str | None = None,
    texte: str | None = None,
) -> str:
    """Le titre à montrer. Identique au titre d'origine quand il est sain."""
    t = (titre or "").strip()
    if t and not est_titre_casse(t):
        return t
    if t and _SEPARATEUR_FINAL.search(t) and not _MOT_COUPE.search(t):
        propre = _SEPARATEUR_FINAL.sub("", t).strip(" -–—")
        if propre and not est_titre_casse(propre):
            return propre
    if t and _MOT_COUPE.search(t):
        complet = completer_mot_coupe(t, texte)
        if complet:
            return complet
        # Sans la fin du mot, on retire le fragment plutôt que de l'afficher.
        sans_fragment = re.sub(r"\s*\S+-$", "", t).rstrip(" ,;:")
        if len(sans_fragment) >= 8:
            return f"{sans_fragment}…"
    if precedent and not est_titre_casse(precedent) and not est_repli(precedent):
        base = re.sub(r"\s*\(suite\)$", "", precedent)
        return f"{base} (suite)"
    if page_start and page_end and page_end != page_start:
        return f"Pages {page_start} à {page_end}"
    if page_start:
        return f"Page {page_start}"
    return "Sans titre"
