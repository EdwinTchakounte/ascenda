"""Enregistre un lot de citations de chapitre rédigées en session.

Une citation n'a de valeur que si elle est authentique. Le script refuse donc
tout lot dont une seule citation ne se retrouve pas, mot pour mot, dans le texte
du chapitre. La comparaison ignore la ponctuation, les espaces et la casse :
l'OCR du corpus coupe les mots en fin de ligne et sème des espaces parasites,
mais la suite des lettres, elle, ne ment pas.

Format attendu : une liste d'objets
  [{"chapitre": "<8 premiers caractères de l'uuid>",
    "citations": [{"texte": ..., "page": 42, "axe": "<slug d'axe>",
                   "theme": ..., "portee": ...}, ...]}]

Un chapitre sans citation exploitable se déclare explicitement, pour que le
registre reste honnête :
  {"chapitre": "...", "citations": [], "motif": "<raison>"}

  python3 pipeline/derive/save_citations.py --doc <uuid> --file lot.json
"""
import sys, json, re, argparse, unicodedata
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

CLES_CITATION = {"texte", "page", "axe", "theme", "portee"}
MIN, MAX = 40, 700   # en deçà on cite un fragment, au delà on recopie une page

def empreinte(s: str) -> str:
    """Réduit un texte à sa seule suite de lettres et de chiffres, accents ôtés."""
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"[^0-9a-z]", "", s.lower())

a = argparse.ArgumentParser()
a.add_argument("--doc", required=True); a.add_argument("--file", required=True)
a.add_argument("--model", default="claude-opus-5 (hors API)")
a.add_argument("--force", action="store_true")
a = a.parse_args()

lot = json.loads(Path(a.file).read_text())
conn = pg()
with conn.cursor() as cur:
    cur.execute("select id from document where id::text like %s", (a.doc + "%",))
    r = cur.fetchone()
if not r: sys.exit("document introuvable")
doc = r[0]

with conn.cursor() as cur:
    cur.execute("select id from chapter where document_id=%s", (doc,))
    connus = {str(x[0]): x[0] for x in cur.fetchall()}
    cur.execute("select slug from axis")
    axes = {x[0] for x in cur.fetchall()}

# --- validation avant toute écriture : un lot passe en entier ou pas du tout
resolus, erreurs, total = [], [], 0
for i, bloc in enumerate(lot):
    court = str(bloc.get("chapitre", ""))
    cible = [v for k, v in connus.items() if k.startswith(court)]
    if len(cible) != 1:
        erreurs.append(f"bloc {i} : chapitre '{court}' introuvable ou ambigu"); continue
    cits = bloc.get("citations", [])
    if not cits:
        if bloc.get("motif"):
            resolus.append((cible[0], [], bloc["motif"])); continue
        erreurs.append(f"bloc {i} : aucune citation"); continue

    with conn.cursor() as cur:
        cur.execute("select string_agg(text, ' ' order by ord) from chunk where chapter_id=%s",
                    (cible[0],))
        source = empreinte(cur.fetchone()[0] or "")

    for j, c in enumerate(cits):
        ref = f"bloc {i} citation {j}"
        intrus = set(c) - CLES_CITATION
        if intrus: erreurs.append(f"{ref} : cle(s) inconnue(s) {sorted(intrus)}")
        t = str(c.get("texte", ""))
        if not MIN <= len(t) <= MAX:
            erreurs.append(f"{ref} : longueur {len(t)} hors bornes {MIN}-{MAX}")
        if c.get("axe") not in axes:
            erreurs.append(f"{ref} : axe inconnu '{c.get('axe')}'")
        if not c.get("theme"): erreurs.append(f"{ref} : theme manquant")
        if not c.get("portee"): erreurs.append(f"{ref} : portee manquante")
        if not isinstance(c.get("page"), int):
            erreurs.append(f"{ref} : page doit être un entier")
        # Le tiret cadratin est proscrit dans ce qu'ASCENDA rédige, pas dans ce
        # qu'ASCENDA cite : une citation doit rester le texte de l'auteur.
        for k in ("theme", "portee"):
            if "—" in str(c.get(k, "")) or "–" in str(c.get(k, "")):
                erreurs.append(f"{ref} : tiret cadratin interdit dans {k}")
        if t and empreinte(t) not in source:
            erreurs.append(f"{ref} : introuvable dans le chapitre >>> {t[:70]}...")
    resolus.append((cible[0], cits, None)); total += len(cits)

if erreurs:
    print("\n".join(erreurs[:20])); sys.exit(f"\n{len(erreurs)} erreur(s), rien enregistré")

with conn.cursor() as cur:
    for cid, cits, motif in resolus:
        if a.force:
            cur.execute("""update derivative set superseded_by=id
                           where chapter_id=%s and kind='citation' and superseded_by is null""", (cid,))
        cur.execute("""insert into derivative (document_id, chapter_id, kind, content,
                         model_id, prompt_version, cost_tokens_in, cost_tokens_out)
                       values (%s,%s,'citation',%s,%s,'citation-v1',0,0)""",
                    (doc, cid, json.dumps({"citations": cits, "motif": motif} if motif
                                          else {"citations": cits}, ensure_ascii=False), a.model))
conn.commit()
print(f"{len(resolus)} chapitres, {total} citations vérifiées et enregistrées")
