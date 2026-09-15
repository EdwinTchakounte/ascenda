"""Enregistre un dérivé produit hors API dans la base."""
import sys, json, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

a = argparse.ArgumentParser()
a.add_argument("--doc"); a.add_argument("--kind", required=True)
a.add_argument("--file", required=True); a.add_argument("--level")
a.add_argument("--chapter"); a.add_argument("--model", default="claude-opus-5 (hors API)")
a = a.parse_args()
data = json.loads(Path(a.file).read_text())
conn = pg()
with conn.cursor() as cur:
    cur.execute("""insert into derivative (document_id, chapter_id, kind, level, content,
                     model_id, prompt_version, cost_tokens_in, cost_tokens_out)
                   values (%s,%s,%s,%s,%s,%s,'v1',0,0) returning id""",
                (a.doc, a.chapter, a.kind, a.level, json.dumps(data, ensure_ascii=False), a.model))
    did = cur.fetchone()[0]
    if a.kind == "fiche_lecture":
        # La fiche est le référentiel bibliographique validé : elle fait autorité
        # sur le titre, les auteurs et l'année, que l'extraction avait souvent ratés.
        cur.execute("""update document set
                         title_clean=%s, authors=%s, year=coalesce(%s, year),
                         biblio_confidence=greatest(coalesce(biblio_confidence,0), 0.95),
                         biblio_validated=true
                       where id=%s""",
                    (data["titre_normalise"], json.dumps(data["auteurs"], ensure_ascii=False),
                     data.get("annee"), a.doc))
        cur.execute("""insert into document_pedagogy (document_id, level, doc_type, target_audience,
                         central_thesis, key_ideas, reading_time_min)
                       values (%s,%s,%s,%s,%s,%s,
                         -- Même règle que le chronogramme (planner.minutes_estimees) :
                         -- le texte extrait, avec un plancher de 60 jetons par page.
                         (select round(greatest(coalesce(sum(k.token_count), 0), d.page_count * 60) * 0.75 / 200)
                            from document d left join chunk k on k.document_id = d.id
                           where d.id = %s group by d.page_count))
                       on conflict (document_id) do update set level=excluded.level,
                         doc_type=excluded.doc_type, target_audience=excluded.target_audience,
                         central_thesis=excluded.central_thesis, key_ideas=excluded.key_ideas,
                         reading_time_min=excluded.reading_time_min""",
                    (a.doc, data["niveau"], data["type_ouvrage"], data["public_cible"],
                     data["these_centrale"], json.dumps(data["idees_force"], ensure_ascii=False), a.doc))
        for c in data["concepts_cles"]:
            cur.execute("insert into concept (term, definition) values (%s,%s) on conflict (term) do nothing",
                        (c["terme"], c["definition"]))
conn.commit()
print(f"dérivé {a.kind} enregistré : {did}")
