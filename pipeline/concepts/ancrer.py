"""Ancre les notions du glossaire dans le texte du corpus."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg  # noqa: E402

# En deçà, un terme est trop court pour être cherché sans bruit : « IA » se
# retrouve dans « biais », « aujourd'hui » et un millier d'autres mots.
LONGUEUR_MIN = 5

# Au-delà, la liste n'apprend plus rien au lecteur et alourdit la table.
MAX_PAR_CONCEPT = 30

# Tournures qui signalent une définition plutôt qu'une simple mention.
# L'apostrophe est doublée : la chaîne part telle quelle dans du SQL.
DEFINITOIRES = r"(est |sont |designe|se definit|consiste|signifie|appelle|" \
               r"nomme|c''est |, a savoir|correspond a)"

SQL_ANCRAGE = f"""
insert into concept_occurrence (concept_id, chunk_id, is_definition)
select o.concept_id, o.chunk_id, o.definition
from (
  select c.id as concept_id, k.id as chunk_id,
         (substr(k.norme, position(c.terme_norme in k.norme) + length(c.terme_norme), 60)
            ~ '{DEFINITOIRES}') as definition,
         row_number() over (
           partition by c.id
           order by (substr(k.norme, position(c.terme_norme in k.norme) + length(c.terme_norme), 60)
                       ~ '{DEFINITOIRES}') desc, k.document_id, k.ord
         ) as rang
    from (select id, term, unaccent(lower(term)) as terme_norme
            from concept where length(term) >= %s) c
    -- Le tsvector sert de préfiltre : l'index GIN élimine en quelques
    -- millisecondes les passages qui ne contiennent aucun mot du terme. Sans
    -- lui, on normalise 11 395 textes pour chacune des 610 notions.
    join lateral (
      select k.id, k.document_id, k.ord, unaccent(lower(k.text)) as norme
        from chunk k
       where k.tsv @@ phraseto_tsquery('french', c.term)
       limit 400
    ) k on position(c.terme_norme in k.norme) > 0
) o
where o.rang <= %s
on conflict (concept_id, chunk_id) do nothing
"""


def etat(conn) -> dict:
    with conn.cursor() as cur:
        cur.execute("""
            select (select count(*) from concept),
                   (select count(*) from concept_occurrence),
                   (select count(distinct concept_id) from concept_occurrence),
                   (select count(*) from concept_occurrence where is_definition)
        """)
        c, o, cc, d = cur.fetchone()
    return {"concepts": c, "occurrences": o, "concepts_ancres": cc, "definitions": d}


def main() -> None:
    p = argparse.ArgumentParser(description="Ancre les notions dans le texte.")
    p.add_argument("--verifier", action="store_true", help="afficher l'état sans écrire")
    p.add_argument("--refaire", action="store_true", help="vider avant de reconstruire")
    a = p.parse_args()

    conn = pg()
    avant = etat(conn)
    print(f"Avant : {avant['occurrences']} occurrences pour "
          f"{avant['concepts_ancres']}/{avant['concepts']} notions.")
    if a.verifier:
        return

    with conn.cursor() as cur:
        if a.refaire:
            cur.execute("delete from concept_occurrence")
            print("Table vidée.")
        print("Ancrage en cours (une à deux minutes)...", flush=True)
        cur.execute(SQL_ANCRAGE, (LONGUEUR_MIN, MAX_PAR_CONCEPT))
    conn.commit()

    apres = etat(conn)
    print(f"Après : {apres['occurrences']} occurrences pour "
          f"{apres['concepts_ancres']}/{apres['concepts']} notions, "
          f"dont {apres['definitions']} définitions.")
    orphelines = apres["concepts"] - apres["concepts_ancres"]
    if orphelines:
        print(f"{orphelines} notions restent sans occurrence : leur terme est trop "
              f"court, ou il ne figure pas littéralement dans le corpus.")


if __name__ == "__main__":
    main()
