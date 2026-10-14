"""Socle partagé des suites de vérification."""
import json
import os
import random
import string
import time
import urllib.error
import urllib.request

BASE = os.getenv("ASCENDA_API", "http://127.0.0.1:8250")


def suffixe(n: int = 6) -> str:
    return "".join(random.choices(string.ascii_lowercase, k=n))


def appel(methode, chemin, corps=None, jeton=None, brut=False, delai=90):
    """Un appel HTTP. Retourne (code, corps décodé, durée en secondes)."""
    donnees = corps if brut else (json.dumps(corps).encode() if corps is not None else None)
    requete = urllib.request.Request(BASE + chemin, data=donnees, method=methode)
    requete.add_header("Content-Type", "application/json")
    if jeton:
        requete.add_header("Authorization", f"Bearer {jeton}")
    debut = time.time()
    try:
        with urllib.request.urlopen(requete, timeout=delai) as r:
            contenu = r.read()
            if not contenu:
                return r.status, None, time.time() - debut
            try:
                return r.status, json.loads(contenu), time.time() - debut
            except ValueError:
                # Un PDF, par exemple : on renvoie sa taille plutôt que son contenu.
                return r.status, {"_octets": len(contenu)}, time.time() - debut
    except urllib.error.HTTPError as e:
        contenu = e.read()
        try:
            return e.code, json.loads(contenu), time.time() - debut
        except ValueError:
            return e.code, None, time.time() - debut
    except Exception as e:  # noqa: BLE001
        return 0, {"_erreur": str(e)[:90]}, time.time() - debut


def compte_neuf(nom="test"):
    """Ouvre un compte jetable et retourne (email, jeton, rafraichissement)."""
    email = f"{nom}-{suffixe()}@example.com"
    code, r, _ = appel("POST", "/v1/auth/inscription", {
        "email": email, "mot_de_passe": "lecture-guidee-2026", "nom": "Vérification",
    })
    if code != 201:
        raise SystemExit(f"Impossible d'ouvrir un compte : {code} {r}")
    return email, r["jetons"]["access_token"], r["jetons"]["refresh_token"]


class Bilan:
    """Accumule les vérifications et rend un verdict lisible."""

    def __init__(self, titre: str):
        self.titre = titre
        self.lignes: list[tuple[bool, str, str]] = []

    def section(self, nom: str) -> None:
        print(f"\n{nom}")

    def verifier(self, libelle: str, condition: bool, detail: str = "") -> bool:
        self.lignes.append((bool(condition), libelle, str(detail)))
        marque = "  OUI  " if condition else "  NON  "
        print(f"{marque}{libelle:46} {detail}")
        return bool(condition)

    def verdict(self) -> int:
        """Affiche le résumé et retourne le code de sortie."""
        echecs = [(l, d) for ok, l, d in self.lignes if not ok]
        print("\n" + "=" * 92)
        print(f"{self.titre} : {len(self.lignes) - len(echecs)} sur {len(self.lignes)}")
        if echecs:
            print("\nÉCHECS")
            for libelle, detail in echecs:
                print(f"  {libelle}\n      {detail}")
        return 1 if echecs else 0
