"""Vérifie que les applications appellent des routes qui existent."""
import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

RACINE = Path(__file__).resolve().parents[2]
CONTRAT = RACINE / "packages" / "shared" / "openapi.json"
API = "http://127.0.0.1:8250"

APPELS = [
    re.compile(r"""\.(?:get|post|put|patch|delete)\(\s*['"](/[^'"]*)['"]"""),
    re.compile(r"""_uri\(\s*['"](/[^'"]*)['"]"""),
    re.compile(r"""recuperer<[^>]*>\(\s*[`'"]([^`'"]+)[`'"]"""),
]


def normaliser(chemin: str) -> str:
    """Ramène une URL composée à la forme du schéma."""
    chemin = chemin.split("?")[0].rstrip("/")
    if not chemin.startswith("/v1"):
        chemin = "/v1" + chemin
    # Interpolations Dart et TypeScript, et paramètres de schéma.
    chemin = re.sub(r"\$\{[^}]+\}|\$\w+|\{[^}]+\}", "{}", chemin)
    return chemin


def chemins_du_schema(schema: dict) -> set[str]:
    return {normaliser(p) for p in schema["paths"]}


def chemins_appeles() -> dict[str, set[str]]:
    """Les chemins trouvés dans le code, par fichier."""
    trouves: dict[str, set[str]] = {}
    sources = [
        *(RACINE / "apps" / "mobile" / "lib").rglob("*.dart"),
        *(RACINE / "apps" / "web-vitrine" / "src").rglob("*.ts"),
        *(RACINE / "apps" / "web-vitrine" / "src").rglob("*.tsx"),
    ]
    for f in sources:
        texte = f.read_text(errors="ignore")
        for motif in APPELS:
            for m in motif.finditer(texte):
                brut = m.group(1)
                if not brut.startswith("/"):
                    continue
                trouves.setdefault(str(f.relative_to(RACINE)), set()).add(normaliser(brut))
    return trouves


def charger_schema(depuis_api: bool) -> dict:
    if depuis_api:
        with urllib.request.urlopen(f"{API}/openapi.json", timeout=20) as r:
            return json.loads(r.read())
    if not CONTRAT.exists():
        raise SystemExit("Aucun contrat figé. Lancer avec --figer, API démarrée.")
    return json.loads(CONTRAT.read_text())


def main() -> None:
    p = argparse.ArgumentParser(description="Confronte les appels au schéma de l'API.")
    p.add_argument("--figer", action="store_true",
                   help="relire le schéma depuis l'API et l'enregistrer")
    p.add_argument("--vif", action="store_true",
                   help="comparer au schéma de l'API plutôt qu'au fichier figé")
    a = p.parse_args()

    if a.figer:
        schema = charger_schema(depuis_api=True)
        CONTRAT.write_text(json.dumps(schema, ensure_ascii=False, indent=2))
        print(f"Contrat figé : {len(schema['paths'])} chemins dans {CONTRAT.name}.")
        return

    schema = charger_schema(depuis_api=a.vif)
    connus = chemins_du_schema(schema)
    appeles = chemins_appeles()

    inconnus: list[tuple[str, str]] = []
    total = 0
    for fichier, chemins in sorted(appeles.items()):
        for c in sorted(chemins):
            total += 1
            if c not in connus:
                inconnus.append((fichier, c))

    print(f"{total} appels relevés dans {len(appeles)} fichiers, "
          f"{len(connus)} routes au schéma.")
    if inconnus:
        print("\nAPPELS SANS ROUTE CORRESPONDANTE")
        for fichier, chemin in inconnus:
            print(f"  {chemin}\n      {fichier}")
        sys.exit(1)
    print("Aucune dérive : tout ce que les applications appellent existe.")


if __name__ == "__main__":
    main()
