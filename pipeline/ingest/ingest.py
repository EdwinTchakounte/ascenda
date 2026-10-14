"""Ingestion ASCENDA : fichier -> MinIO + document/chapter/chunk dans Postgres."""
import sys, os, re, json, uuid, hashlib, argparse, traceback
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import (ROOT, LIVRES, PIPELINE_VERSION, pg, s3, BUCKET,
                    sha256_file, clean_title, norm)

CHARS_PER_TOKEN = 3.3          # français, mesuré sur le corpus
TARGET_TOKENS   = 750
OVERLAP_TOKENS  = 100
SCAN_THRESHOLD  = 400          # chars/page en dessous duquel l'OCR est requis

AXIS_FROM_DIR = {}             # rempli depuis le nom des répertoires

# ---------------------------------------------------------------- extraction
def extract_pdf(path):
    import pymupdf
    doc = pymupdf.open(path)
    pages = []
    for i, p in enumerate(doc):
        pages.append(norm(p.get_text("text")))
    toc = doc.get_toc(simple=True) or []
    meta = doc.metadata or {}
    n = doc.page_count
    doc.close()
    return pages, toc, meta, n

def extract_epub(path):
    from ebooklib import epub, ITEM_DOCUMENT
    from bs4 import BeautifulSoup
    book = epub.read_epub(path, options={"ignore_ncx": True})
    pages, toc = [], []
    for item in book.get_items():
        if item.get_type() != ITEM_DOCUMENT:
            continue
        soup = BeautifulSoup(item.get_content(), "lxml")
        txt = norm(soup.get_text("\n"))
        if len(txt.strip()) < 40:
            continue
        h = soup.find(re.compile("^h[1-3]$"))
        if h and h.get_text(strip=True):
            toc.append([1, h.get_text(strip=True)[:200], len(pages) + 1])
        pages.append(txt)
    meta = {}
    try:
        meta["title"] = (book.get_metadata("DC", "title") or [[None]])[0][0]
        meta["author"] = (book.get_metadata("DC", "creator") or [[None]])[0][0]
        meta["language"] = (book.get_metadata("DC", "language") or [[None]])[0][0]
    except Exception:
        pass
    return pages, toc, meta, len(pages)

# ---------------------------------------------------------------- chunking
def build_chunks(pages, chapters):
    """Chunks ~750 tokens, alignés sur les frontières de chapitre, avec overlap.
    Chaque chunk connaît ses pages -> l'agent peut citer « p. 47 »."""
    def chap_of(page):
        cur = None
        for c in chapters:
            if c["page_start"] <= page:
                cur = c
            else:
                break
        return cur

    chunks, buf, buf_pages, buf_chap = [], [], [], None
    tgt = int(TARGET_TOKENS * CHARS_PER_TOKEN)
    ovl = int(OVERLAP_TOKENS * CHARS_PER_TOKEN)

    def flush():
        nonlocal buf, buf_pages, buf_chap
        if not buf:
            return
        text = "\n".join(buf).strip()
        if len(text) < 200:
            buf, buf_pages = [], []
            return
        chunks.append(dict(
            text=text, page_start=min(buf_pages), page_end=max(buf_pages),
            chapter_key=buf_chap,
            token_count=int(len(text) / CHARS_PER_TOKEN),
            content_hash=hashlib.sha256(text.encode()).hexdigest(),
        ))
        # La reprise commence sur un début de mot : coupée au caractère près,
        # elle ouvrait le passage suivant sur un fragment (« ère Les textes… »).
        tail = text[-ovl:] if len(text) > ovl else ""
        espace = tail.find(" ")
        tail = tail[espace + 1:] if 0 <= espace < 40 else tail
        buf = [tail] if tail else []
        buf_pages = [max(buf_pages)] if tail else []

    for i, txt in enumerate(pages, start=1):
        if not txt.strip():
            continue
        c = chap_of(i)
        key = c["key"] if c else None
        if key != buf_chap:
            flush()
            # Un chapitre ne commence pas par la fin du précédent.
            buf, buf_pages = [], []
            buf_chap = key
        buf.append(txt)
        buf_pages.append(i)
        if sum(len(x) for x in buf) >= tgt:
            flush()
    flush()
    return chunks

def build_chapters(toc, n_pages):
    out = []
    for idx, entry in enumerate(toc):
        lvl, title, page = entry[0], entry[1], entry[2]
        if not title or page < 1:
            continue
        out.append(dict(key=f"c{idx}", ord=idx, level=lvl,
                        title=title.strip()[:400], page_start=int(page)))
    out.sort(key=lambda c: (c["page_start"], c["ord"]))
    for i, c in enumerate(out):
        c["page_end"] = (out[i + 1]["page_start"] - 1) if i + 1 < len(out) else n_pages
        if c["page_end"] < c["page_start"]:
            c["page_end"] = c["page_start"]
    return out

# ---------------------------------------------------------------- droits
def guess_rights(path: Path, title: str):
    """Heuristique conservatrice : par défaut 'restricted', non redistribuable.
    Seuls les documents institutionnels identifiés passent en 'institutional'."""
    name = path.name.lower()
    inst = any(k in name for k in ("men_dne", "ciesd", "cours-", "lexique", "brochure"))
    if inst:
        return "institutional", True, 100000
    return "restricted", False, 1200

# ---------------------------------------------------------------- main
def ingest_one(conn, client, path: Path, axis_slug: str, force=False):
    sha = sha256_file(path)
    with conn.cursor() as cur:
        cur.execute("select id, pipeline_version from document where sha256=%s and owner_id is null", (sha,))
        row = cur.fetchone()
        if row and row[1] >= PIPELINE_VERSION and not force:
            return ("skip", row[0], 0)

    ext = path.suffix.lower()
    if ext == ".pdf":
        pages, toc, meta, n = extract_pdf(path)
        engine = "pymupdf"
    elif ext == ".epub":
        pages, toc, meta, n = extract_epub(path)
        engine = "ebooklib"
    else:
        return ("unsupported", None, 0)

    chars = sum(len(p) for p in pages)
    cpp = chars / max(n, 1)
    has_text = cpp >= SCAN_THRESHOLD
    ocr_status = "none" if has_text else "needed"

    title_clean, author_guess, year, conf = clean_title(path.name)
    if meta.get("title") and len(str(meta["title"]).strip()) > 4:
        mt = str(meta["title"]).strip()
        if not re.match(r"^(untitled|microsoft word|document)", mt, re.I):
            title_clean, conf = mt, min(0.95, conf + 0.1)
    authors = [a for a in [author_guess or meta.get("author")] if a]

    copyright_status, redistributable, max_excerpt = guess_rights(path, title_clean)
    storage_key = f"{axis_slug}/{sha[:2]}/{sha}{ext}"
    client.fput_object(BUCKET, storage_key, str(path))

    chapters = build_chapters(toc, n)
    chunks = build_chunks(pages, chapters) if has_text else []

    with conn.cursor() as cur:
        cur.execute("delete from document where sha256=%s and owner_id is null", (sha,))
        cur.execute("""
            insert into document (sha256, filename_original, mime, size_bytes, page_count,
              language, source, visibility, storage_key,
              title_raw, title_clean, authors, year, biblio_confidence,
              has_text_layer, ocr_status, extraction_engine, extracted_chars,
              chars_per_page, quality_score, ingested_at, pipeline_version,
              copyright_status, redistributable, max_excerpt_chars, origin_node)
            values (%s,%s,%s,%s,%s,%s,'corpus_base','private',%s,
                    %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,now(),%s,%s,%s,%s,'local')
            returning id""",
            (sha, path.name, "application/pdf" if ext == ".pdf" else "application/epub+zip",
             path.stat().st_size, n, meta.get("language") or "fr", storage_key,
             path.stem, title_clean, json.dumps(authors), year, conf,
             has_text, ocr_status, engine, chars, round(cpp, 1),
             round(min(1.0, cpp / 2200), 3), PIPELINE_VERSION,
             copyright_status, redistributable, max_excerpt))
        doc_id = cur.fetchone()[0]

        cur.execute("select id from axis where slug=%s", (axis_slug,))
        a = cur.fetchone()
        if a:
            cur.execute("""insert into document_axis (document_id, axis_id, weight, assigned_by, confidence)
                           values (%s,%s,1.0,'curator',1.0)""", (doc_id, a[0]))

        keymap = {}
        for c in chapters:
            cur.execute("""insert into chapter (document_id, ord, title, page_start, page_end)
                           values (%s,%s,%s,%s,%s) returning id""",
                        (doc_id, c["ord"], c["title"], c["page_start"], c["page_end"]))
            keymap[c["key"]] = cur.fetchone()[0]

        for i, ch in enumerate(chunks):
            cur.execute("""insert into chunk (document_id, chapter_id, ord, page_start, page_end,
                             text, token_count, content_hash, pipeline_version)
                           values (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                        (doc_id, keymap.get(ch["chapter_key"]), i, ch["page_start"],
                         ch["page_end"], ch["text"], ch["token_count"],
                         ch["content_hash"], PIPELINE_VERSION))
    conn.commit()
    return ("ok", doc_id, len(chunks))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--fichier", help="n'ingérer que ce fichier (relatif à livres/)")
    args = ap.parse_args()

    if args.fichier:
        cible = (LIVRES / args.fichier).resolve()
        # Le chemin vient d'une requête : on refuse tout ce qui sort de livres/.
        if not str(cible).startswith(str(LIVRES.resolve())) or not cible.is_file():
            print(f"Fichier introuvable ou hors du corpus : {args.fichier}")
            sys.exit(1)
        conn, client = pg(), s3()
        slug = cible.parent.name.lower()
        with conn.cursor() as cur:
            cur.execute("""insert into axis (slug, label) values (%s, %s)
                           on conflict (slug) do nothing""",
                        (slug, re.sub(r"^\d{2}-", "", cible.parent.name).replace("-", " ")))
        conn.commit()
        statut, doc_id, nch = ingest_one(conn, client, cible, slug, args.force)
        print(f"{cible.name} : {statut}" + (f", {nch} chapitres" if nch else ""))
        conn.close()
        sys.exit(0 if statut != "erreur" else 1)

    conn, client = pg(), s3()
    dirs = sorted(d for d in LIVRES.iterdir()
                  if d.is_dir() and re.match(r"^\d{2}-", d.name))
    # créer les axes
    with conn.cursor() as cur:
        for i, d in enumerate(dirs):
            slug = d.name.lower()
            label = re.sub(r"^\d{2}-", "", d.name).replace("-", " ")
            cur.execute("""insert into axis (slug,label,sort_order) values (%s,%s,%s)
                           on conflict (slug) do nothing""", (slug, label, i))
    conn.commit()

    total, done, failed = 0, 0, []
    for d in dirs:
        slug = d.name.lower()
        files = sorted(f for f in d.iterdir() if f.suffix.lower() in (".pdf", ".epub"))
        for f in files:
            if args.limit and total >= args.limit:
                break
            total += 1
            try:
                status, doc_id, nch = ingest_one(conn, client, f, slug, args.force)
                print(f"[{total:3d}] {status:11s} {nch:4d} chunks  {f.name[:70]}", flush=True)
                if status == "ok":
                    done += 1
            except Exception as e:
                conn.rollback()
                failed.append((f.name, repr(e)))
                print(f"[{total:3d}] ERREUR      {f.name[:70]} :: {e}", flush=True)
    print(f"\n=== {done}/{total} ingérés, {len(failed)} échecs ===")
    for n, e in failed:
        print("  !", n, "->", e[:160])
    conn.close()

if __name__ == "__main__":
    main()
