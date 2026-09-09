"""Avancement de la production des QCM."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

conn = pg()
with conn.cursor() as cur:
    cur.execute("""
      with ch as (select ch.id, ch.document_id, coalesce(sum(k.token_count),0) tok
                  from chapter ch left join chunk k on k.chapter_id=ch.id group by ch.id),
           u as (select document_id, count(*) utiles from ch where tok>=300 group by 1),
           f as (select document_id, count(distinct chapter_id) faits,
                        count(*) filter (where true) lots
                 from derivative where kind='quiz' and superseded_by is null
                   and chapter_id is not null group by 1),
           q as (select d.document_id, sum(jsonb_array_length(d.content->'questions')) n
                 from derivative d where d.kind='quiz' and d.superseded_by is null group by 1)
      select left(coalesce(d.title_clean,d.title_raw),44) titre,
             u.utiles, coalesce(f.faits,0) faits, coalesce(q.n,0) questions
      from document d join u on u.document_id=d.id
      left join f on f.document_id=d.id left join q on q.document_id=d.id
      where not exists (select 1 from document o where o.supersedes_document_id=d.id)
      order by (coalesce(f.faits,0)::float/u.utiles) desc, u.utiles desc""")
    rows = cur.fetchall()
tot_u = sum(r[1] for r in rows); tot_f = sum(r[2] for r in rows); tot_q = sum(r[3] for r in rows)
print(f"{'ouvrage':46}{'utiles':>7}{'faits':>7}{'QCM':>7}")
for t, u, f, q in rows:
    print(f"{t:46}{u:>7}{f:>7}{q:>7}")
print(f"\n{len(rows)} ouvrages | {tot_f}/{tot_u} chapitres ({100*tot_f/max(tot_u,1):.1f} %) | {tot_q} questions")
