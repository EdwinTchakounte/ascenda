"""File de production des fiches, par valeur pédagogique décroissante."""
import sys, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

# Poids d'axe : les ouvrages qui structurent un parcours passent avant les guides d'outils.
POIDS = {"04-ia-societe-ethique-philosophie":100, "02-ia-technique-academique":95,
         "01-ia-fondamentaux-vulgarisation":90, "07-afrique-histoire-pensee":85,
         "09-developpement-personnel-influence":75, "08-litterature-romans":70,
         "06-ia-travail-management-metiers":65, "05-ia-education-pedagogie":60,
         "03-ia-outils-pratique-prompting":50, "10-economie-entrepreneuriat-finance":45,
         "11-sciences-environnement":40}

a = argparse.ArgumentParser(); a.add_argument("--kind", default="fiche_lecture")
a.add_argument("--todo", action="store_true"); a.add_argument("--limit", type=int, default=0)
a = a.parse_args()
conn = pg()
with conn.cursor() as cur:
    cur.execute("""
      select d.id, d.title_clean, d.page_count, ax.slug,
             exists(select 1 from derivative dv where dv.document_id=d.id and dv.kind=%s) faite
      from document d
      join document_axis da on da.document_id=d.id join axis ax on ax.id=da.axis_id
      where d.has_text_layer and d.ocr_status in ('none','done')
        and not exists (select 1 from document n where n.supersedes_document_id = d.id)
      order by d.page_count desc""", (a.kind,))
    rows = cur.fetchall()
rows = [r for r in rows if not (a.todo and r[4])]
rows.sort(key=lambda r: (-POIDS.get(r[3],0), -(r[2] or 0)))
if a.limit: rows = rows[:a.limit]
for i,(did,t,pc,slug,faite) in enumerate(rows,1):
    print(f"{i:3d}\t{did}\t{pc:4d}p\t{slug[:6]}\t{'[fait]' if faite else '      '}\t{(t or '')[:62]}")
print(f"\n{len(rows)} document(s)")
