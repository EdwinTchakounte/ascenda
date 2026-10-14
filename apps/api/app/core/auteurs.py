"""Les auteurs tels qu'on les montre au public."""
import re

_ATTENTE = re.compile(r"^\s*(auteur|auteurs?)\s+(à|a)\s+identifier\s*$|^\s*(auteur\s+)?inconnu\s*$|^\s*n/?a\s*$", re.I)


def auteurs(valeurs: list[str] | None) -> list[str]:
    return [v for v in (valeurs or []) if v and v.strip() and not _ATTENTE.match(v)]
