"""Extrait un lot de chapitres in extenso pour la rédaction de QCM."""
import sys, re, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

SEUIL = 300   # en deçà, un chapitre ne porte pas deux questions

def chapitres(conn, doc_id):
    with conn.cursor() as cur:
        cur.execute("""select ch.id, ch.ord, ch.title, ch.page_start, ch.page_end,
                              coalesce(sum(k.token_count),0) tok
                       from chapter ch left join chunk k on k.chapter_id=ch.id
                       where ch.document_id=%s group by ch.id order by ch.ord""", (doc_id,))
        return cur.fetchall()

def texte(conn, chap_id):
    with conn.cursor() as cur:
        cur.execute("select page_start,page_end,text from chunk where chapter_id=%s order by ord",(chap_id,))
        return cur.fetchall()

def replier(t):
    """Recolle les lignes que l'OCR a coupées mot par mot."""
    t = re.sub(r"[ \t]+\n", "\n", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    t = re.sub(r"(?<![\n])\n(?![\n])", " ", t)
    return re.sub(r"[ \t]{2,}", " ", t).strip()

def sans_recouvrement(precedent, suivant, fenetre=1400):
    """Les chunks se chevauchent : on coupe la reprise en tete du suivant."""
    if not precedent: return suivant
    queue = precedent[-260:]
    for n in range(len(queue), 40, -20):
        i = suivant.find(queue[-n:], 0, fenetre)
        if i != -1:
            return suivant[i + n:].lstrip()
    return suivant

def deja_fait(conn, doc_id, genre="quiz"):
    """Chapitres déjà pourvus du dérivé demandé. Un ouvrage entièrement
    couvert en QCM reste à couvrir en citations : le genre change le reste."""
    with conn.cursor() as cur:
        cur.execute("""select chapter_id from derivative
                       where document_id=%s and kind=%s and superseded_by is null
                         and chapter_id is not null""", (doc_id, genre))
        return {r[0] for r in cur.fetchall()}

if __name__ == "__main__":
    a = argparse.ArgumentParser()
    a.add_argument("--doc", required=True)
    a.add_argument("--from", dest="depart", type=int, default=0)
    a.add_argument("--budget", type=int, default=14000)
    a.add_argument("--out")
    a.add_argument("--max-chap", dest="max_chap", type=int, default=10000)
    a.add_argument("--kind", default="quiz", choices=["quiz", "citation"],
                   help="dérivé déjà produit à ignorer (quiz par défaut)")
    a = a.parse_args()

    conn = pg()
    with conn.cursor() as cur:
        cur.execute("select id from document where id::text like %s", (a.doc + "%",))
        r = cur.fetchone()
    if not r: sys.exit("document introuvable")
    doc = r[0]
    with conn.cursor() as cur:
        cur.execute("""select coalesce(d.title_clean,d.title_raw), d.authors, d.year
                       from document d where d.id=%s""", (doc,))
        titre, auteurs, annee = cur.fetchone()

    faits = deja_fait(conn, doc, a.kind)
    tous = chapitres(conn, doc)
    utiles = [c for c in tous if c[5] >= SEUIL and c[0] not in faits and c[1] >= a.depart]

    lot, cout = [], 0
    for c in utiles:
        if lot and cout + c[5] > a.budget: break
        lot.append(c); cout += c[5]
    if not lot:
        print(f"RIEN À FAIRE  ({len(tous)} chapitres, {len(faits)} déjà traités)"); sys.exit(0)

    out = [f"OUVRAGE : {titre}",
           f"AUTEUR(S) : {', '.join(auteurs or []) or 'inconnu'}   ANNÉE : {annee or 'inconnue'}",
           f"DOCUMENT : {doc}",
           f"LOT : {len(lot)} chapitres, ord {lot[0][1]} à {lot[-1][1]}, {cout} tokens",
           f"RESTE APRÈS CE LOT : {len(utiles) - len(lot)} chapitres utiles", ""]
    for cid, ord_, t, ps, pe, tok in lot:
        out.append(f"\n{'='*72}\n### CHAPITRE {ord_}  [{str(cid)[:8]}]  {t or '(sans titre)'}"
                   f"   p. {ps}-{pe}   {tok} tokens\n{'='*72}")
        morceaux = texte(conn, cid)
        if tok > a.max_chap and len(morceaux) > 3:
            # chapitre trop long pour une lecture integrale : on echantillonne
            # en gardant toujours le debut et la fin, et on le signale.
            pas = 2
            while pas < len(morceaux):
                garde = [morceaux[0]] + morceaux[1:-1][::pas] + [morceaux[-1]]
                if sum(len(m[2]) for m in garde) / 4 <= a.max_chap: break
                pas += 1
            morceaux = garde
            out[-1] += (f"\n[LECTURE PARTIELLE : {len(morceaux)} passages retenus sur "
                        f"{len(texte(conn, cid))}. N'interroger que sur ce qui est lu.]")
        precedent = ""
        for cps, cpe, txt in morceaux:
            txt = replier(txt)
            txt = sans_recouvrement(precedent, txt)
            if not txt.strip(): continue
            precedent += " " + txt
            out.append(f"\n[p. {cps}-{cpe}] {txt}")
    txt = "\n".join(out)
    if a.out:
        Path(a.out).write_text(txt); print(f"{a.out}  ({cout} tokens, {len(lot)} chapitres, reste {len(utiles)-len(lot)})")
    else:
        print(txt)
