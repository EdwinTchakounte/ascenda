"""OCR des documents sans couche texte, puis ré-ingestion.
Écrit une version OCRisée à côté de l'original (suffixe .ocr.pdf) et bascule
document.storage_key dessus. Idempotent : ne retraite pas ocr_status='done'."""
import sys, subprocess, shutil
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import ROOT, LIVRES, pg

OCR = ROOT / ".venv/bin/ocrmypdf"

def targets(conn):
    with conn.cursor() as cur:
        cur.execute("""select id, filename_original, page_count, chars_per_page
                       from document where ocr_status='needed' order by page_count""")
        return cur.fetchall()

def find_file(name):
    hits = list(LIVRES.rglob(name))
    return hits[0] if hits else None

def main():
    conn = pg()
    rows = targets(conn)
    print(f"{len(rows)} documents à OCRiser\n", flush=True)
    for doc_id, name, pages, cpp in rows:
        src = find_file(name)
        if not src:
            print(f"  introuvable: {name}", flush=True); continue
        out = src.with_suffix(".ocr.pdf")
        with conn.cursor() as cur:
            cur.execute("update document set ocr_status='running' where id=%s", (doc_id,))
        conn.commit()
        print(f"→ {name[:60]} ({pages} p, {cpp} c/p)", flush=True)
        cmd = [str(OCR), "-l", "fra+eng", "--optimize", "1", "--skip-text",
               "--jobs", "4", "--output-type", "pdf", str(src), str(out)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        ok = r.returncode == 0 and out.exists()
        with conn.cursor() as cur:
            if ok:
                cur.execute("""update document set ocr_status='done', ocr_engine='tesseract-5/ocrmypdf-17',
                               pipeline_version=0 where id=%s""", (doc_id,))
                print(f"   OK -> {out.name}", flush=True)
            else:
                cur.execute("update document set ocr_status='failed' where id=%s", (doc_id,))
                print(f"   ECHEC: {(r.stderr or '')[-300:]}", flush=True)
        conn.commit()
    conn.close()
    print("\nOCR terminé. Relancer : .venv/bin/python pipeline/ingest/ingest.py", flush=True)

if __name__ == "__main__":
    main()
