"""Réinjecte le texte des PDF OCRisés dans le document EXISTANT (même id)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ingest"))
from common import pg, s3, BUCKET, LIVRES, PIPELINE_VERSION
from ingest import extract_pdf, build_chapters, build_chunks, SCAN_THRESHOLD

conn, client = pg(), s3()
with conn.cursor() as cur:
    cur.execute("""select id, filename_original, storage_key from document
                   where ocr_status in ('done','failed','needed') order by page_count""")
    rows = cur.fetchall()

for doc_id, name, key in rows:
    src = Path(name).with_suffix(".ocr.pdf").name
    hits = list(LIVRES.rglob(src))
    if not hits:
        print(f"  pas de .ocr.pdf pour {name[:55]}"); continue
    p = hits[0]
    try:
        pages, toc, meta, n = extract_pdf(p)
    except Exception as e:
        print(f"  illisible {src[:55]} :: {e}"); continue
    chars = sum(len(x) for x in pages); cpp = chars / max(n, 1)
    # Un export de diapositives a légitimement peu de texte par page
    seuil = 250 if '.pptx' in name.lower() else SCAN_THRESHOLD
    if cpp < seuil:
        print(f"  OCR insuffisant ({cpp:.0f} c/p) {src[:50]}")
        continue
    chapters = build_chapters(toc, n)
    chunks = build_chunks(pages, chapters)
    newkey = key.rsplit(".", 1)[0] + ".ocr.pdf"
    client.fput_object(BUCKET, newkey, str(p))
    with conn.cursor() as cur:
        cur.execute("delete from chunk where document_id=%s", (doc_id,))
        cur.execute("delete from chapter where document_id=%s", (doc_id,))
        cur.execute("""update document set has_text_layer=true, ocr_status='done',
                         extracted_chars=%s, chars_per_page=%s, page_count=%s,
                         quality_score=%s, storage_key=%s, pipeline_version=%s,
                         extraction_engine='pymupdf/ocr' where id=%s""",
                    (chars, round(cpp,1), n, round(min(1.0, cpp/2200),3),
                     newkey, PIPELINE_VERSION, doc_id))
        km = {}
        for c in chapters:
            cur.execute("""insert into chapter (document_id, ord, title, page_start, page_end)
                           values (%s,%s,%s,%s,%s) returning id""",
                        (doc_id, c["ord"], c["title"], c["page_start"], c["page_end"]))
            km[c["key"]] = cur.fetchone()[0]
        for i, ch in enumerate(chunks):
            cur.execute("""insert into chunk (document_id, chapter_id, ord, page_start, page_end,
                             text, token_count, content_hash, pipeline_version)
                           values (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                        (doc_id, km.get(ch["chapter_key"]), i, ch["page_start"], ch["page_end"],
                         ch["text"], ch["token_count"], ch["content_hash"], PIPELINE_VERSION))
    conn.commit()
    print(f"  OK {cpp:6.0f} c/p  {len(chunks):4d} chunks  {name[:52]}")
print("terminé")
