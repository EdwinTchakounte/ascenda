"""Le PDF dans le lecteur : servi entier pour les ouvrages redistribuables, refusé pour les
autres.
"""
import sys
import urllib.request
import uuid
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "tests"))

from commun import BASE, appel  # noqa: E402

_resultats = []


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


def fichier(document_id):
    try:
        with urllib.request.urlopen(f"{BASE}/v1/lecteur/{document_id}/pdf", timeout=120) as r:
            return r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read()


ouvrages = []
for page in range(1, 6):
    st, l, _ = appel("GET", f"/v1/bibliotheque?page={page}")
    if st != 200 or not l["ouvrages"]:
        break
    ouvrages += l["ouvrages"]
fiches = [appel("GET", f"/v1/bibliotheque/{o['id']}")[1] for o in ouvrages]
libres = [f for f in fiches if f["droits"]["pdf"]]
proteges = [f for f in fiches if not f["droits"]["lecture_integrale"]]

print("\n· La fiche")
ok("des ouvrages proposent leur PDF", len(libres) > 0, len(libres))
ok("aucun ouvrage protégé ne le propose",
   all(not f["droits"]["pdf"] for f in proteges) and len(proteges) > 0, len(proteges))

print("\n· Les ouvrages redistribuables")
for f in libres:
    st, entetes, corps = fichier(f["id"])
    annonce = int(entetes.get("Content-Length") or -1)
    ok(f"{f['titre'][:60]} : PDF complet",
       st == 200 and corps[:5] == b"%PDF-" and b"%%EOF" in corps[-64:] and annonce == len(corps),
       (st, len(corps), annonce))
    ok(f"{f['titre'][:60]} : la fiche annonce sa taille réelle",
       f["droits"].get("pdf_octets") == len(corps), (f["droits"].get("pdf_octets"), len(corps)))
    _, sommaire, _ = appel("GET", f"/v1/bibliotheque/{f['id']}/sommaire")
    chapitres = sommaire.get("chapitres", sommaire) if isinstance(sommaire, dict) else sommaire
    if chapitres:
        _, lec, _ = appel("GET", f"/v1/lecteur/{f['id']}/chapitre/{chapitres[0]['id']}")
        ok(f"{f['titre'][:60]} : le lecteur propose d'ouvrir la page dans le PDF",
           lec["droits"].get("pdf") is True, lec["droits"])

print("\n· Les ouvrages protégés")
for f in proteges[:5]:
    ok(f"{f['titre'][:60]} : ni taille ni PDF annoncés", f["droits"].get("pdf_octets") is None)
    st, _, corps = fichier(f["id"])
    ok(f"{f['titre'][:60]} : refusé, avec l'explication",
       st == 403 and b"%PDF" not in corps and "redistribuable".encode() in corps, (st, corps[:80]))

print("\n· Les identifiants")
st, _, _ = fichier(uuid.uuid4())
ok("un ouvrage inconnu répond 404", st == 404, st)
st, _, corps = fichier("pas-un-identifiant")
ok("un identifiant mal formé répond 404, sans erreur serveur", st == 404, (st, corps[:80]))

print("\n" + "=" * 92)
_echecs = [x for x in _resultats if not x[0]]
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
