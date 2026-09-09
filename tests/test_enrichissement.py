"""La chaîne d'enrichissement, sans appeler le modèle.

Ce module est celui par lequel le corpus grandit : chaque ouvrage ajouté devra
passer par lui. Ce qu'on vérifie ici n'est donc pas la qualité de ce que le
modèle écrit, mais les quatre propriétés sans lesquelles une chaîne de
génération ne se réutilise pas.

- Elle **s'appelle** : les options que le module par ouvrage passe existent.
- Elle **ne refait pas** ce qui est déjà produit.
- Elle **remplace** au lieu d'empiler.
- Elle **annonce son coût** avant de le dépenser.

Rien ici ne consomme un jeton : on s'arrête juste avant l'appel au modèle.
"""
import subprocess
import sys
import uuid
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "pipeline"))
sys.path.insert(0, str(RACINE / "pipeline" / "derive"))
sys.path.insert(0, str(RACINE / "pipeline" / "livre"))

from common import pg  # noqa: E402
import derive  # noqa: E402
import etat as etat_module  # noqa: E402

PYTHON = str(RACINE / ".venv" / "bin" / "python")
_resultats = []


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


conn = pg()

print("\n· Les sept types sont complets")
for kind in sorted(derive.SCHEMAS):
    a_schema = kind in derive.SCHEMAS
    a_consigne = kind in derive.CONSIGNES or kind == "fiche_lecture"
    ok(f"{kind} a son schéma et sa consigne", a_schema and a_consigne,
       "" if a_consigne else "consigne manquante")

print("\n· Le module par ouvrage sait appeler le moteur")
# La régression qui a rendu le module inutilisable : produire.py passait --doc
# et --kind, que derive.py ne connaissait pas. argparse sortait en code 2 avant
# le premier appel au modèle, et personne ne l'a vu parce que le contrôle de
# clé s'arrêtait juste avant.
r = subprocess.run(
    [PYTHON, "pipeline/derive/derive.py", "--doc", "0000", "--kind", "quiz", "--estimer"],
    capture_output=True, text=True, cwd=RACINE,
)
ok("les options de produire.py sont acceptées", r.returncode == 0,
   (r.stderr.strip().splitlines() or [""])[-1])

with conn.cursor() as cur:
    cur.execute("""select d.id, coalesce(d.title_clean, d.title_raw)
                     from document d
                    where d.takedown_status = 'none'
                      and exists (select 1 from derivative v
                                   where v.document_id = d.id and v.kind = 'quiz'
                                     and v.superseded_by is null)
                    limit 1""")
    doc_id, titre = cur.fetchone()
prefixe = str(doc_id)[:8]

print(f"\n· Ce qui existe n'est pas refait  ({titre[:40]})")
restants = derive.pick_jobs(conn, ["quiz"], doc=prefixe)
tous = derive.pick_jobs(conn, ["quiz"], doc=prefixe, refaire=True)
ok("le moteur écarte les quiz déjà produits", len(restants) < len(tous),
   f"{len(restants)} restants sur {len(tous)} chapitres")
ok("--refaire les reprend tous", len(tous) > 0, f"{len(tous)}")

print("\n· L'appareil du livre n'est pas facturé")
with conn.cursor() as cur:
    cur.execute("""select count(*) from chapter c
                    where c.document_id = %s
                      and coalesce(c.token_count,0) < %s
                      and exists (select 1 from chunk k where k.chapter_id = c.id)""",
                (doc_id, derive.TOKENS_MIN_CHAPITRE))
    courts = cur.fetchone()[0]
vises = {j.get("chapter_id") for j in tous}
with conn.cursor() as cur:
    cur.execute("""select c.id from chapter c
                    where c.document_id = %s and coalesce(c.token_count,0) < %s""",
                (doc_id, derive.TOKENS_MIN_CHAPITRE))
    petits = {r[0] for r in cur.fetchall()}
ok("aucun chapitre sous le seuil n'est visé", not (vises & petits),
   f"{courts} chapitre(s) court(s) écarté(s)")
ok("le seuil est celui du planificateur et de l'état",
   derive.TOKENS_MIN_CHAPITRE == etat_module.TOKENS_MIN,
   f"{derive.TOKENS_MIN_CHAPITRE} et {etat_module.TOKENS_MIN}")

print("\n· Enregistrer remplace au lieu d'empiler")
with conn.cursor() as cur:
    cur.execute("""select c.id from chapter c
                    where c.document_id = %s and coalesce(c.token_count,0) >= %s
                    order by c.ord limit 1""", (doc_id, derive.TOKENS_MIN_CHAPITRE))
    chap = cur.fetchone()[0]

# On travaille sur un type dont le corpus ne porte encore aucune ligne : ainsi
# la suite n'a rien à restaurer, et elle ne peut pas abîmer un vrai dérivé.
TYPE_ESSAI = "compte_rendu"


def actifs():
    with conn.cursor() as cur:
        cur.execute("""select count(*) from derivative
                        where document_id = %s and chapter_id = %s and kind = %s
                          and superseded_by is null""", (doc_id, chap, TYPE_ESSAI))
        return cur.fetchone()[0]


faux = {"essai": str(uuid.uuid4())}
ok("aucun dérivé de ce type au départ", actifs() == 0, actifs())
premier = derive.save(conn, doc_id, chap, TYPE_ESSAI, None, faux, (10, 20))
ok("un seul dérivé actif après le premier enregistrement", actifs() == 1, actifs())
second = derive.save(conn, doc_id, chap, TYPE_ESSAI, None, faux, (10, 20))
ok("toujours un seul après le second", actifs() == 1, actifs())
with conn.cursor() as cur:
    cur.execute("select superseded_by from derivative where id = %s", (premier,))
    remplace = cur.fetchone()[0]
ok("l'ancien pointe vers celui qui le remplace", str(remplace) == str(second), f"{remplace}")

# Ménage : les deux lignes partent ensemble, la clé étrangère de l'une vers
# l'autre disparaissant avec elles.
with conn.cursor() as cur:
    cur.execute("delete from derivative where id = any(%s)", ([premier, second],))
conn.commit()
ok("la suite ne laisse rien derrière elle", actifs() == 0, actifs())

print("\n· Le coût s'annonce avant de se dépenser")
r = subprocess.run(
    [PYTHON, "pipeline/derive/derive.py", "--doc", prefixe, "--kind", "citation", "--estimer"],
    capture_output=True, text=True, cwd=RACINE,
)
sortie = r.stdout
ok("l'estimation sort sans erreur", r.returncode == 0)
ok("elle chiffre l'entrée et la sortie", "jetons (comptés)" in sortie and "estimés" in sortie)
ok("elle donne le prix en direct et en batch", "en direct" in sortie and "en batch" in sortie)
ok("elle avertit que le tarif est à vérifier", "vérifier" in sortie)
ok("aucun dérivé n'a été produit au passage", "dérivés enregistrés" not in sortie)

conn.close()

print("\n" + "=" * 92)
_echecs = [x for x in _resultats if not x[0]]
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
