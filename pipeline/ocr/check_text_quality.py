"""Détecte les couches texte corrompues (police sans table ToUnicode).

chars_per_page ne suffit pas : un PDF peut produire beaucoup de caractères
et n'être que du bruit. On mesure la part de lettres et la fréquence des mots
français courants — un texte réel en contient toujours.
"""
import sys, re, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

MOTS = re.compile(r"\b(?:de|la|le|les|des|du|et|un|une|est|dans|pour|que|qui|"
                  r"sur|par|plus|pas|au|aux|ce|cette|il|elle|nous|vous|"
                  r"the|of|and|to|in|is|that|for)\b", re.I)

def score(txt: str):
    if len(txt) < 200:
        return 0.0, 0.0
    lettres = sum(c.isalpha() or c.isspace() for c in txt) / len(txt)
    mots = len(MOTS.findall(txt))
    densite = mots / (len(txt) / 1000)          # mots courants pour 1000 car.
    return round(lettres, 3), round(densite, 1)

a = argparse.ArgumentParser(); a.add_argument("--fix", action="store_true")
a = a.parse_args()
conn = pg()
with conn.cursor() as cur:
    cur.execute("""select d.id, d.title_clean, d.filename_original,
                          string_agg(c.text, ' ' order by c.ord)
                   from document d join chunk c on c.document_id=d.id
                   where d.has_text_layer group by d.id
                   """)
    rows = cur.fetchall()

suspects = []
for doc_id, titre, fichier, txt in rows:
    lettres, densite = score(txt or "")
    # Un texte français normal : > 0.80 de lettres/espaces, > 25 mots courants /1000c
    if lettres < 0.78 or densite < 15:
        suspects.append((doc_id, titre, fichier, lettres, densite))

print(f"{len(rows)} documents analysés, {len(suspects)} suspects\n")
for doc_id, titre, fichier, l, d in sorted(suspects, key=lambda r: r[3]):
    print(f"  lettres={l:.2f} mots/1000c={d:5.1f}  {(titre or fichier)[:58]}")
    if a.fix:
        with conn.cursor() as cur:
            cur.execute("""update document set ocr_status='needed', has_text_layer=false,
                             quality_score=%s where id=%s""", (l, doc_id))
if a.fix:
    conn.commit()
    print("\nMarqués pour OCR forcé.")
