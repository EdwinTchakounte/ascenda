"""Enregistre un lot de QCM de chapitre rédigés en session.

Format attendu : une liste d'objets
  [{"chapitre": "<8 premiers caractères de l'uuid>",
    "questions": [{"q": ..., "choix": [4 items], "reponse": 0..3,
                   "explication": ..., "niveau": ..., "page": 12}, ...]}]

  python3 pipeline/derive/save_quiz.py --doc <uuid> --file lot.json
"""
import sys, json, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg

NIVEAUX = {"restitution", "comprehension", "application"}
CLES_QUESTION = {"q", "choix", "reponse", "explication", "niveau", "page"}

a = argparse.ArgumentParser()
a.add_argument("--doc", required=True); a.add_argument("--file", required=True)
a.add_argument("--model", default="claude-opus-5 (hors API)")
a.add_argument("--force", action="store_true")
a = a.parse_args()

lot = json.loads(Path(a.file).read_text())
conn = pg()
with conn.cursor() as cur:
    cur.execute("select id from document where id::text like %s", (a.doc + "%",))
    r = cur.fetchone()
if not r: sys.exit("document introuvable")
doc = r[0]

with conn.cursor() as cur:
    cur.execute("select id from chapter where document_id=%s", (doc,))
    connus = {str(x[0]): x[0] for x in cur.fetchall()}

# --- validation avant toute écriture : un lot passe en entier ou pas du tout
resolus, erreurs, total = [], [], 0
for i, bloc in enumerate(lot):
    court = str(bloc.get("chapitre", ""))
    cible = [v for k, v in connus.items() if k.startswith(court)]
    if len(cible) != 1:
        erreurs.append(f"bloc {i} : chapitre '{court}' {'ambigu' if cible else 'introuvable'}"); continue
    qs = bloc.get("questions") or []
    if not qs:
        # un chapitre sans matière (appareil éditorial, table, index) se solde
        # par un enregistrement vide motivé : le registre reste honnête.
        if bloc.get("motif"):
            resolus.append((cible[0], [], bloc["motif"])); continue
        erreurs.append(f"bloc {i} : aucune question"); continue
    for j, q in enumerate(qs):
        ref = f"bloc {i} question {j}"
        # Une cle mal orthographiee passerait inapercue et polluerait la banque.
        intrus = set(q) - CLES_QUESTION
        if intrus: erreurs.append(f"{ref} : cle(s) inconnue(s) {sorted(intrus)}")
        if len(q.get("choix", [])) != 4: erreurs.append(f"{ref} : il faut exactement 4 choix")
        if not isinstance(q.get("reponse"), int) or not 0 <= q["reponse"] <= 3:
            erreurs.append(f"{ref} : reponse doit être un entier de 0 à 3")
        if len(set(q.get("choix", []))) != len(q.get("choix", [])):
            erreurs.append(f"{ref} : deux choix identiques")
        if not q.get("explication"): erreurs.append(f"{ref} : explication manquante")
        if q.get("niveau") not in NIVEAUX: erreurs.append(f"{ref} : niveau invalide")
        for c in ("q", "explication"):
            if "—" in str(q.get(c, "")) or "–" in str(q.get(c, "")):
                erreurs.append(f"{ref} : tiret cadratin interdit dans {c}")
    resolus.append((cible[0], qs, None)); total += len(qs)

if erreurs:
    print("\n".join(erreurs[:20])); sys.exit(f"\n{len(erreurs)} erreur(s), rien enregistré")

# Les rédacteurs mettent la bonne réponse en premier : on mélange les choix à
# l'enregistrement, de façon déterministe (même outil que pour le corpus).
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "apps" / "api"))
from app.outils.melanger_choix import MARQUE, melanger  # noqa: E402

with conn.cursor() as cur:
    for cid, qs, motif in resolus:
        qs = melanger(qs, str(cid))
        if a.force:
            cur.execute("""update derivative set superseded_by=id
                           where chapter_id=%s and kind='quiz' and superseded_by is null""", (cid,))
        cur.execute("""insert into derivative (document_id, chapter_id, kind, content,
                         model_id, prompt_version, cost_tokens_in, cost_tokens_out)
                       values (%s,%s,'quiz',%s,%s,'qcm-v1',0,0)""",
                    (doc, cid, json.dumps({"questions": qs, "motif": motif} if motif
                                          else {"questions": qs, MARQUE: True}, ensure_ascii=False), a.model))
conn.commit()
print(f"{len(resolus)} chapitres, {total} questions enregistrées")
