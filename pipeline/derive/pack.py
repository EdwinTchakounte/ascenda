"""Extrait un pack de contexte échantillonné pour un document, vers stdout ou fichier."""
import sys, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

def pack(conn, doc_id, budget):
    with conn.cursor() as cur:
        cur.execute("""select d.title_clean, d.authors, d.year, d.page_count,
                              coalesce(string_agg(distinct a.label,', '),'')
                       from document d left join document_axis da on da.document_id=d.id
                       left join axis a on a.id=da.axis_id where d.id=%s group by d.id""",(doc_id,))
        t,au,y,p,ax = cur.fetchone()
        cur.execute("select ord,title,page_start,page_end from chapter where document_id=%s order by ord limit 60",(doc_id,))
        chaps = cur.fetchall()
        cur.execute("select page_start,page_end,text,token_count from chunk where document_id=%s order by ord",(doc_id,))
        rows = cur.fetchall()
    total = sum(r[3] or 0 for r in rows)
    keep = rows
    if total > budget:
        # stride incrémental : on vise le budget par le haut sans le diviser par deux
        stride = 1
        while stride < len(rows):
            stride += 1
            keep = rows[::stride]
            if sum(r[3] or 0 for r in keep) <= budget:
                break
    used = sum(r[3] or 0 for r in keep)
    som = "\n".join(f"  {c[1]} (p. {c[2]}-{c[3]})" for c in chaps) or "  (non structuré)"
    head = (f"OUVRAGE : {t}\nAUTEUR(S) : {', '.join(au or []) or 'inconnu'}\nANNÉE : {y or 'inconnue'}\n"
            f"PAGES : {p}\nAXE : {ax}\nSOMMAIRE :\n{som}\n"
            f"\n[{len(keep)}/{len(rows)} passages, {used} tokens sur {total}]\n")
    body = "\n\n---\n\n".join(f"[p. {r[0]}-{r[1]}]\n{r[2]}" for r in keep)
    return head + "\n=== EXTRAITS ===\n\n" + body, used

if __name__ == "__main__":
    a = argparse.ArgumentParser(); a.add_argument("--title"); a.add_argument("--id")
    a.add_argument("--budget", type=int, default=0); a.add_argument("--out")
    a = a.parse_args()
    conn = pg()
    with conn.cursor() as cur:
        if a.id: cur.execute("select id from document where id=%s",(a.id,))
        else: cur.execute("select id from document where title_clean ilike %s order by page_count desc limit 1",(f"%{a.title}%",))
        r = cur.fetchone()
    if not r: sys.exit("document introuvable")
    budget = a.budget
    if not budget:  # adaptatif : ~90 tokens de contexte par page, borné
        with conn.cursor() as cur:
            cur.execute("select page_count from document where id=%s", (r[0],))
            pc = cur.fetchone()[0] or 100
        budget = min(26000, max(8000, int(pc * 60)))
    txt, used = pack(conn, r[0], budget)
    if a.out: Path(a.out).write_text(txt); print(f"{a.out}  ({used} tokens, doc {r[0]})")
    else: print(txt)
