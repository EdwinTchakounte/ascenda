"""Rendre ses accents à un texte français écrit sans."""
import math
import re
import unicodedata
from collections import Counter, defaultdict

_MOT = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿŒœ]+")

# Après un sujet, « a » est le verbe avoir : « il a », « qui a », « l'IA a ».
_SUJETS = {"il", "elle", "on", "qui", "y", "cela", "ca", "chacun", "n", "lui", "ia", "auteur", "auteure", "homme", "livre", "ouvrage", "chatgpt", "machine", "modele",
           "algorithme", "entreprise", "texte", "monde", "societe", "chapitre", "systeme", "humanite",
           "technologie", "internet", "science", "recherche", "etat", "europe", "afrique", "occident"}


_ARTICLES = {"un", "une", "le", "la", "les", "des", "du", "son", "sa", "ses", "leur", "leurs", "cette", "ces",
             "notre", "nos", "votre", "vos", "mon", "ma", "mes"}
_AUXILIAIRES = {"est", "sont", "a", "ont", "ete", "etait", "etaient", "etre", "avoir", "avait", "avaient", "sera",
                "seront", "fut", "furent", "ai", "as", "avons", "avez", "suis", "es", "sommes", "etes", "ayant",
                "etant", "se", "s", "bien", "tres", "plus", "moins", "deja", "souvent", "mal"}


# Deux mots français distincts, avec et sans accent : le mode sûr ne les touche
# jamais, seul le contexte peut trancher (« ça marche », « le marché »).
_HOMOGRAPHES = {"marche", "marches", "cote", "cotes", "tache", "taches", "peche", "peches", "foret", "forets",
                "jeune", "jeunes", "mur", "murs", "pale", "sur", "sure", "du", "des", "la", "ou", "a", "mais",
                "colle", "cree", "crees", "retraite", "legue", "roder", "boite", "chasse", "cure", "interesse",
                "presente", "presentes", "reserve", "reserves", "separe", "age", "ages"}


def plier(mot: str) -> str:
    """« Été » et « ete » ont la même forme pliée : « ete »."""
    return unicodedata.normalize("NFKD", mot).encode("ascii", "ignore").decode().lower()


class Accentueur:
    def __init__(self) -> None:
        self.formes: dict[str, Counter] = defaultdict(Counter)
        self.avant: Counter = Counter()  # (mot précédent plié, forme)
        self.apres: Counter = Counter()  # (forme, mot suivant plié)

    def apprendre(self, texte: str) -> None:
        mots = [m.lower() for m in _MOT.findall(texte)]
        for i, m in enumerate(mots):
            self.formes[plier(m)][m] += 1
            if i:
                self.avant[(plier(mots[i - 1]), m)] += 1
            if i + 1 < len(mots):
                self.apres[(m, plier(mots[i + 1]))] += 1

    def _choisir(self, mot: str, precedent: str | None, suivant: str | None) -> str:
        bas = mot.lower()
        variantes = self.formes.get(plier(bas))
        if not variantes:
            return mot
        # Un mot déjà accentué, ou qu'aucune variante accentuée ne concurrence,
        # ne se touche pas.
        if bas != plier(bas) or set(variantes) == {bas}:
            return mot

        def score(v: str) -> float:
            s = math.log(variantes[v] + 1)
            if precedent:
                s += 2 * math.log(self.avant[(plier(precedent), v)] + 1)
            if suivant:
                s += 2 * math.log(self.apres[(v, plier(suivant))] + 1)
            return s

        if bas == "a" and precedent and plier(precedent) in _SUJETS:
            return mot
        # Verbe inversé : « fonde-t-il », « adopte-t-elle » restent au présent.
        if suivant and plier(suivant) in {"t", "il", "elle", "on", "ils", "elles"} and bas.endswith("e"):
            return mot
        choix = max(variantes, key=score)
        if choix == bas:
            return mot
        if bas not in ("a", "ou") and variantes.get(bas, 0) >= 5 and score(choix) < score(bas) + 1.5:
            return mot
        if (choix.endswith(("é", "és")) and bas.endswith(("e", "es")) and suivant
                and plier(suivant) in _ARTICLES
                and not (precedent and plier(precedent) in _AUXILIAIRES)):
            return mot
        # Après un pronom sujet, un verbe au présent ne devient pas un participe
        # sans auxiliaire : « il plagie », pas « il plagié ».
        if (precedent and plier(precedent) in {"il", "elle", "on", "je", "tu", "qui", "cela", "ca"}
                and bas.endswith(("e", "es", "ent")) and choix.endswith(("é", "ée", "és", "ées"))):
            return mot
        # On garde la casse : « Etre » devient « Être », « ETAPE » devient « ÉTAPE ».
        if mot.isupper() and len(mot) > 1:
            return choix.upper()
        if mot[0].isupper():
            return choix[0].upper() + choix[1:]
        return choix

    def sur(self, mot: str) -> str:
        """Le mot accentué seulement s'il n'y a pas d'ambiguïté : une variante
        accentuée domine nettement (« qualité »), et non deux (« présente » et
        « présenté »)."""
        bas = mot.lower()
        if bas != plier(bas) or bas in _HOMOGRAPHES:
            return mot
        variantes = self.formes.get(bas)
        if not variantes:
            return mot
        total = sum(variantes.values())
        choix, n = variantes.most_common(1)[0]
        if choix == bas or variantes.get(bas, 0) > total * 0.25 or n < total * 0.7 or total < 5:
            return mot
        if mot.isupper() and len(mot) > 1:
            return choix.upper()
        return choix[0].upper() + choix[1:] if mot[0].isupper() else choix

    def accentuer_sur(self, texte: str) -> str:
        return _MOT.sub(lambda m: self.sur(m.group(0)), texte) if texte else texte

    def accentuer(self, texte: str) -> str:
        if not texte:
            return texte
        mots = list(_MOT.finditer(texte))
        sortie, curseur = [], 0
        for i, m in enumerate(mots):
            precedent = mots[i - 1].group(0) if i else None
            suivant = mots[i + 1].group(0) if i + 1 < len(mots) else None
            sortie.append(texte[curseur:m.start()])
            sortie.append(self._choisir(m.group(0), precedent, suivant))
            curseur = m.end()
        sortie.append(texte[curseur:])
        return "".join(sortie)


def sans_accents(texte: str) -> bool:
    """Une phrase assez longue pour en juger, et qui n'a aucun accent."""
    lettres = [c for c in texte if c.isalpha()]
    return len(lettres) >= 25 and all(c == plier(c) or c.lower() == "œ" for c in lettres if c.lower() == c) \
        and all(plier(c).upper() == c or not c.isupper() for c in lettres)
