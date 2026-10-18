"""Répare l'OCR chiffré de « L'obstacle est le chemin » (Ryan Holiday)."""
import sys, re, math, argparse, unicodedata, collections
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

# les minuscules et quelques glyphes hauts portent les caractères que la police de
ACCENTS = {"p": "é", "q": "è", "r": "ê", "v": "î", "k": "â", "o": "ç",
           "e": "É", "w": "ï", "j": "à", "a": "»", "{": "ô",
           "¿": "fi", "À": "fl", "¶": "’", "±": "–", "©": "«"}
DECALAGE = 29
# une majuscule d'origine se chiffre en ponctuation ou en chiffre
TOKEN = re.compile(r"(^|[\s(«\"'’\-])([\x24-\x3d])?([A-Za-z¿À¶±©{\[\\\]]{1,})", re.M)
CORPS = set("DEFGHIJKLMNOPQRSTUVWXYZ[\\]")
ROMAINS = {"I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII",
           "XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX","XXI"}
ROMAINS |= {r + "e" for r in ROMAINS}
ELISIONS = set("jldnsctm")   # lettres qui s'élident devant une apostrophe
MARGE = 0.35   # écart de vraisemblance exigé pour trancher

def decode(t):
    return "".join(ACCENTS[c] if c in ACCENTS else chr(ord(c) + DECALAGE) for c in t)

def pliage(s):
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if "a" <= c <= "z")

def lexique(textes):
    """Fréquence des formes françaises, apprise sur les ouvrages indemnes."""
    n = collections.Counter()
    for t in textes:
        n.update(m.group().lower() for m in re.finditer(r"[A-Za-zÀ-ÿ]+", t))
    return n

def modele_bigrammes(textes):
    n = collections.Counter()
    for t in textes:
        p = pliage(t)
        n.update(p[i:i+2] for i in range(len(p) - 1))
    total = sum(n.values())
    return n, total

def vraisemblance(mot, n, total):
    p = pliage(mot)
    if len(p) < 2: return 0.0
    s = sum(math.log((n[p[i:i+2]] + 1) / (total + 676)) for i in range(len(p) - 1))
    return s / (len(p) - 1)

def reparer(texte, n, total, mots):
    # 1. les caractères de contrôle ne peuvent être que du chiffré
    texte = "".join(chr(ord(c) + DECALAGE) if 0x03 <= ord(c) <= 0x1e
                    and c not in "\n\r\t" else c for c in texte)

    def signature(t):
        """Un mot chiffré n'emploie que les lettres D à Z, les accents et fi."""
        if not all(c in ACCENTS or c in CORPS for c in t): return False
        # une lettre isolée peut être un accent chiffré : « j » vaut « à »
        return any(c in CORPS for c in t) or len(t) == 1

    def arbitre(m):
        avant, tete, t = m.group(1), m.group(2) or "", m.group(3)
        garder = lambda: avant + tete + t
        if (t in ROMAINS and not tete) or not signature(t): return garder()
        clair = decode(t)
        rendre = lambda: avant + (decode(tete) if tete else "") + clair
        fu, fc = mots.get(t.lower(), 0), mots.get(clair.lower(), 0)
        corps = sum(1 for c in t if c in CORPS)

        # une capitale d'origine chiffrée en ponctuation ne trompe pas
        if tete and (len(t) > 1 or t in CORPS): return rendre()

        if len(t) == 1:
            suite = m.string[m.end():m.end() + 1]
            # une capitale devant une apostrophe
            if suite in "’'":
                return rendre() if t in CORPS and clair in ELISIONS else garder()
            # une lettre isolée entre deux espaces peut être un accent chiffré
            if suite and not suite.isspace(): return garder()
            if not (t.islower() and t.isascii()) and t not in CORPS: return garder()
            # entre deux espaces, le français n'a guère que a, y, à et ô
            if t in CORPS: return rendre() if clair in ("a", "y", "à", "ô") else garder()
            return rendre() if fc > 4 * fu + 3 else garder()
        # les glyphes hauts ne sont des ligatures qu'entourés de lettres chiffrées
        if any(ord(c) > 127 for c in t) and corps >= 1: return rendre()
        if corps < 2:
            # une seule capitale : il faut une attestation écrasante pour trancher
            return rendre() if fc > 20 * fu + 50 else garder()
        coupe = re.match(r"-\n([a-zà-ÿ]+)", m.string[m.end():])
        if coupe:
            q = coupe.group(1)
            fu, fc = mots.get(t.lower() + q, 0), mots.get(clair.lower() + q, 0)
        if any(c in ACCENTS for c in t) and fu == 0: return rendre()
        if fu > 4 * fc + 3: return garder()
        if fc > 4 * fu + 3: return rendre()
        a, b = (t.lower(), clair.lower()) if not coupe else (t.lower() + q, clair.lower() + q)
        return rendre() if vraisemblance(b, n, total) > vraisemblance(a, n, total) + MARGE else garder()

    lignes = []
    for ligne in texte.split("\n"):
        lignes.append(ligne if "http" in ligne or "www." in ligne
                      else TOKEN.sub(arbitre, ligne))
    return "\n".join(lignes)

if __name__ == "__main__":
    a = argparse.ArgumentParser()
    a.add_argument("--doc", required=True)
    a.add_argument("--appliquer", action="store_true")
    a = a.parse_args()

    conn = pg()
    with conn.cursor() as cur:
        cur.execute("select id from document where id::text like %s", (a.doc + "%",))
        r = cur.fetchone()
        if not r: sys.exit("document introuvable")
        doc = r[0]
        # le modèle de langue s'apprend sur les autres ouvrages, indemnes
        cur.execute("""select k.text from chunk k join chapter c on c.id=k.chapter_id
                       where c.document_id <> %s limit 4000""", (doc,))
        propres = [x[0] for x in cur.fetchall()]
        n, total = modele_bigrammes(propres)
        mots = lexique(propres)
        cur.execute("""select k.id, k.text from chunk k join chapter c on c.id=k.chapter_id
                       where c.document_id=%s order by c.ord, k.ord""", (doc,))
        lignes = cur.fetchall()
    print(f"lexique de référence : {len(mots)} formes distinctes, "
          f"modèle de bigrammes : {total} occurrences")

    modifs = [(i, t, reparer(t, n, total, mots)) for i, t in lignes]
    modifs = [m for m in modifs if m[1] != m[2]]
    print(f"{len(modifs)} chunks sur {len(lignes)} à corriger")
    if not a.appliquer:
        i, av, ap = modifs[0]
        print("\n--- AVANT ---\n" + av[200:1100] + "\n\n--- APRÈS ---\n" + ap[200:1100])
        sys.exit("\n(essai seulement, relancer avec --appliquer)")

    with conn.cursor() as cur:
        cur.execute("""create table if not exists chunk_texte_ocr_brut
                       (chunk_id uuid primary key, text text not null,
                        sauvegarde_le timestamptz not null default now())""")
        for i, av, _ in modifs:
            cur.execute("""insert into chunk_texte_ocr_brut (chunk_id, text) values (%s,%s)
                           on conflict (chunk_id) do nothing""", (i, av))
        for i, _, ap in modifs:
            cur.execute("update chunk set text=%s where id=%s", (ap, i))
    conn.commit()
    print(f"{len(modifs)} chunks corrigés, texte d'origine sauvegardé dans chunk_texte_ocr_brut")
