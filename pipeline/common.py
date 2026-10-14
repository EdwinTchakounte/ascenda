"""Socle partagé du pipeline ASCENDA : config, connexions, utilitaires."""
import os, re, hashlib, unicodedata
from pathlib import Path
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")

PIPELINE_VERSION = 1
LIVRES = ROOT / "livres"
DATA = ROOT / "data"

PG = dict(
    host=os.getenv("POSTGRES_HOST", "localhost"),
    port=int(os.getenv("POSTGRES_PORT", 5450)),
    dbname=os.getenv("POSTGRES_DB", "ascenda"),
    user=os.getenv("POSTGRES_USER", "ascenda"),
    password=os.getenv("POSTGRES_PASSWORD", ""),
)

def pg():
    import psycopg
    return psycopg.connect(**PG)

def s3():
    from minio import Minio
    return Minio(
        os.getenv("MINIO_ENDPOINT", "localhost:9250"),
        access_key=os.getenv("MINIO_ROOT_USER"),
        secret_key=os.getenv("MINIO_ROOT_PASSWORD"),
        secure=os.getenv("MINIO_SECURE", "false").lower() == "true",
    )

BUCKET = os.getenv("MINIO_BUCKET", "ascenda-docs")

def sha256_file(p: Path, buf=1 << 20) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(buf), b""):
            h.update(b)
    return h.hexdigest()

NOISE = [
    r"\(z-?library[^)]*\)", r"\(z-lib\.org\)", r"\(PDFDrive\)", r"@\w+FR", r"@lechat",
    r"z-library\.sk", r"1lib\.sk", r"z-lib\.sk", r"\bEBOOK\b", r"_epub\b",
    r"^Informatique\s*\(\d{0,4}\)\s*", r"\(\d\)$", r"-\d$", r"\.pptx$",
]

def clean_title(filename: str):
    """Retourne (title_clean, year, confidence)."""
    t = Path(filename).stem
    year = None
    m = re.search(r"\((19|20)\d{2}\)", t)
    if m:
        year = int(m.group(0)[1:-1])
    hits = 0
    for pat in NOISE:
        t2 = re.sub(pat, " ", t, flags=re.I)
        if t2 != t:
            hits += 1
        t = t2
    t = t.replace("_", " ").replace("’", "'")
    t = re.sub(r"\s*[-–]\s*$", "", t)
    t = re.sub(r"\s{2,}", " ", t).strip(" -–_.")
    # auteur souvent entre parenthèses en fin : « Titre (Auteur) »
    author = None
    m = re.search(r"\(([^()]{3,60})\)\s*$", t)
    if m and not re.search(r"\d{4}", m.group(1)):
        author = m.group(1).strip()
        t = t[: m.start()].strip()
    conf = 0.85 - 0.08 * hits - (0.15 if len(t) < 12 else 0)
    return t, author, year, max(0.1, round(conf, 2))

def norm(s: str) -> str:
    return unicodedata.normalize("NFKC", s).replace("­", "")
