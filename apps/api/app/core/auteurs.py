"""Les auteurs tels qu'on les montre au public.

L'extraction des métadonnées a laissé des valeurs d'attente dans quelques
fiches (« Auteur à identifier »). Ce sont des notes de catalogage, pas des
noms : affichées sur une couverture, elles font passer un ouvrage réel pour
un brouillon. Mieux vaut ne rien écrire que d'écrire cela.
"""
import re

_ATTENTE = re.compile(r"^\s*(auteur|auteurs?)\s+(à|a)\s+identifier\s*$|^\s*(auteur\s+)?inconnu\s*$|^\s*n/?a\s*$", re.I)


def auteurs(valeurs: list[str] | None) -> list[str]:
    return [v for v in (valeurs or []) if v and v.strip() and not _ATTENTE.match(v)]
