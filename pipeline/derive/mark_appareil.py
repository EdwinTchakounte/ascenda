"""Solde les chapitres d'appareil éditorial (copyright, sommaire, index, éloges).

Ces pages passent le seuil de tokens sans porter la moindre matière
interrogeable. On les enregistre comme quiz vides motivés plutôt que de les
laisser gonfler indéfiniment le reste à faire.

  python3 pipeline/derive/mark_appareil.py [--doc <uuid>] [--appliquer]
"""
import sys, re, json, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

MOTIFS = [
 (r"^\s*(copyright|colophon|mentions? l[ée]gales?)", "mentions légales"),
 (r"^\s*(contents?|table (des|of) |sommaire|table des mati)", "table des matières"),
 (r"^\s*(index|glossary|bibliograph|r[ée]f[ée]rences?|notes?)\s*$", "appareil de fin"),
 (r"^\s*(praise|[ée]loges?|ils en parlent|t[ée]moignages?)", "éloges promotionnels"),
 (r"^\s*(title page|half title|page de titre|dedication|d[ée]dicace|epigraph|exergue)", "page liminaire"),
 (r"^\s*(about the author|[àa] propos de l.auteur|l.auteur|biographie de l.auteur)", "notice d'auteur"),
 (r"^\s*(acknowledg|remerciements?)", "remerciements"),
 (r"^\s*(du m[êe]me auteur|other books|also by|dans la m[êe]me collection|catalogue)", "catalogue éditeur"),
 (r"^\s*(annonces?|publicit|bon de commande|order form|newsletter)", "matériel promotionnel"),
]

a = argparse.ArgumentParser()
a.add_argument("--doc"); a.add_argument("--appliquer", action="store_true")
a = a.parse_args()

conn = pg()
sql = """with ch as (select ch.id, ch.document_id, ch.ord, ch.title,
                            coalesce(sum(k.token_count),0) tok
                     from chapter ch left join chunk k on k.chapter_id=ch.id group by ch.id)
         select ch.id, ch.document_id, ch.ord, ch.title, ch.tok,
                left(coalesce(d.title_clean,d.title_raw),40)
         from ch join document d on d.id=ch.document_id
         where ch.tok>=300 and ch.title is not null
           and not exists (select 1 from derivative x where x.chapter_id=ch.id
                             and x.kind='quiz' and x.superseded_by is null)"""
params = []
if a.doc:
    sql += " and ch.document_id::text like %s"; params.append(a.doc + "%")
sql += " order by 6, ch.ord"
with conn.cursor() as cur:
    cur.execute(sql, params); rows = cur.fetchall()

vises = []
for cid, did, ord_, titre, tok, livre in rows:
    for rx, motif in MOTIFS:
        if re.search(rx, titre.strip(), re.I):
            vises.append((cid, did, ord_, titre, tok, livre, motif)); break

for cid, did, ord_, titre, tok, livre, motif in vises:
    print(f"{livre:42} ord {ord_:>4}  {titre[:34]:36} {tok:>5} tok  -> {motif}")
print(f"\n{len(vises)} chapitre(s) d'appareil sur {len(rows)} examinés")

if a.appliquer and vises:
    with conn.cursor() as cur:
        for cid, did, *_ , motif in vises:
            cur.execute("""insert into derivative (document_id, chapter_id, kind, content,
                             model_id, prompt_version, cost_tokens_in, cost_tokens_out)
                           values (%s,%s,'quiz',%s,'filtre mark_appareil','qcm-v1',0,0)""",
                        (did, cid, json.dumps({"questions": [], "motif": motif}, ensure_ascii=False)))
    conn.commit(); print("soldés")
else:
    print("(relancer avec --appliquer pour enregistrer)")
