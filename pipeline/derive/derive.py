"""Génération des dérivés pédagogiques ASCENDA.

Chaque dérivé est ancré : idées-force, quiz et flashcards portent la page et
l'extrait littéral qui les justifient. Rien n'est produit « de mémoire ».

Deux modes :
  --sync   quelques documents, immédiat (mise au point des prompts)
  --batch  tout le corpus via l'API Batches (50 % du prix, < 24 h)
"""
import sys, os, json, argparse, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import pg, ROOT
from schemas import SCHEMAS

MODEL = "claude-opus-5"
PROMPT_VERSION = "v1"
CTX_BUDGET = 320_000        # tokens de contexte alloués au pack par document

SYSTEM = """Tu es le concepteur pédagogique d'ASCENDA, une plateforme de lecture guidée francophone.

Règles absolues :
- Tu ne travailles QUE sur les extraits fournis. Si le texte ne permet pas de répondre, tu le dis dans le champ prévu et tu baisses `confiance`.
- Toute affirmation attribuée à l'ouvrage doit pouvoir être rattachée à une page présente dans les extraits. Si tu n'as pas la page, mets null, n'invente jamais un numéro.
- `extrait_source` est une citation LITTÉRALE, copiée du texte fourni, jamais une reformulation.
- Tu écris en français, dans une langue claire et adulte. Pas de jargon décoratif, pas d'emphase creuse.
- Une idée-force est une thèse de l'auteur, pas un thème abordé. « L'auteur soutient que X » et non « L'auteur parle de X »."""

CONSIGNES = {
  "fiche_lecture": "Produis la fiche de lecture de cet ouvrage. Le lecteur doit savoir en 30 secondes ce que le livre soutient, à qui il s'adresse et ce qu'il va y gagner.",
  "synthese": "Produis une synthèse structurée de cet ouvrage pour un lecteur de niveau {niveau}. Suis le fil de l'auteur, indique les pages de chaque section.",
  "quiz": "Produis un quiz sur ce passage. Équilibre : rappel, compréhension, analyse. Chaque question porte sur une idée réellement présente dans le texte, avec sa citation justificative.",
  "flashcards": "Produis des flashcards de révision espacée sur les notions clés de ce passage. Recto = une question ou un terme, verso = la réponse en deux phrases maximum.",
  "citation": "Relève les passages les plus forts de ce chapitre. Chaque citation est LITTÉRALE, copiée mot pour mot, avec sa page. Choisis ce qui porte une thèse ou une formule mémorable, jamais une phrase de transition.",
  "compte_rendu": "Produis le compte rendu de ce chapitre : ce que l'auteur y établit, dans son ordre, avec les pages. Le lecteur doit pouvoir vérifier qu'il a compris la même chose que toi.",
  "resume_executif": "Produis le résumé exécutif de cet ouvrage : ce qu'un lecteur pressé doit en retenir, et ce qu'il perd à ne pas le lire en entier.",
}

# Tarif du modèle, en dollars par million de jetons. À vérifier chez Anthropic
# avant de s'engager sur un budget : ces valeurs servent à donner un ordre de
# grandeur, pas à établir une facture. Le mode batch coûte la moitié.
TARIF_ENTREE = float(os.getenv("TARIF_ENTREE", "15"))
TARIF_SORTIE = float(os.getenv("TARIF_SORTIE", "75"))
# Sortie moyenne observée par dérivé. Réévaluée dès qu'un lot réel a tourné :
# la table `derivative` porte les jetons de chaque appel.
SORTIE_ESTIMEE = 2500

# ------------------------------------------------------------------ contexte
def context_pack(conn, doc_id, budget=CTX_BUDGET, chapter_id=None):
    """Assemble les extraits d'un document (ou d'un chapitre) sous contrainte de budget.
    Sur un gros ouvrage, on échantillonne régulièrement plutôt que de tronquer au début :
    une synthèse bâtie sur les 100 premières pages est une synthèse fausse."""
    with conn.cursor() as cur:
        if chapter_id:
            cur.execute("""select ord, page_start, page_end, text, token_count
                           from chunk where chapter_id=%s order by ord""", (chapter_id,))
        else:
            cur.execute("""select ord, page_start, page_end, text, token_count
                           from chunk where document_id=%s order by ord""", (doc_id,))
        rows = cur.fetchall()
    if not rows:
        return None, 0
    total = sum(r[4] or 0 for r in rows)
    if total <= budget:
        keep = rows
    else:
        step = total / budget
        keep, acc, i = [], 0, 0
        stride = max(1, int(round(step)))
        keep = rows[::stride]
        while sum(r[4] or 0 for r in keep) > budget and len(keep) > 4:
            keep = keep[::2]
    parts = [f"[p. {r[1]}-{r[2]}]\n{r[3]}" for r in keep]
    used = sum(r[4] or 0 for r in keep)
    note = "" if total <= budget else \
        f"\n\n(Extraits échantillonnés régulièrement sur l'ensemble de l'ouvrage : {len(keep)}/{len(rows)} passages.)"
    return "\n\n---\n\n".join(parts) + note, used

def doc_header(conn, doc_id):
    with conn.cursor() as cur:
        cur.execute("""select d.title_clean, d.authors, d.year, d.page_count,
                              coalesce(string_agg(distinct a.label, ', '), '')
                       from document d
                       left join document_axis da on da.document_id=d.id
                       left join axis a on a.id=da.axis_id
                       where d.id=%s group by d.id""", (doc_id,))
        t, au, y, p, ax = cur.fetchone()
        cur.execute("""select ord, title, page_start, page_end from chapter
                       where document_id=%s order by ord limit 80""", (doc_id,))
        chaps = cur.fetchall()
    som = "\n".join(f"  {c[1]} (p. {c[2]}-{c[3]})" for c in chaps) or "  (non structuré)"
    return (f"OUVRAGE : {t}\nAUTEUR(S) : {', '.join(au or []) or 'inconnu'}\n"
            f"ANNÉE : {y or 'inconnue'}\nPAGES : {p}\nAXE : {ax}\nSOMMAIRE :\n{som}")

def build_prompt(conn, doc_id, kind, chapter_id=None, niveau="intermediaire"):
    pack, used = context_pack(conn, doc_id, chapter_id=chapter_id)
    if not pack:
        return None, 0
    consigne = CONSIGNES[kind].format(niveau=niveau)
    return (f"{doc_header(conn, doc_id)}\n\n=== EXTRAITS ===\n\n{pack}\n\n"
            f"=== CONSIGNE ===\n{consigne}"), used

# ------------------------------------------------------------------ stockage
def save(conn, doc_id, chapter_id, kind, level, data, usage):
    """Enregistre un dérivé et retire de la circulation celui qu'il remplace.

    La colonne `superseded_by` existait sans que rien ne la pose : régénérer un
    quiz aurait dû créer un second lot actif à côté du premier. En pratique
    l'index unique partiel `ux_derivative_naturelle` le refusait, et la
    régénération échouait purement et simplement.

    On retire donc l'ancien de la circulation avant d'insérer le nouveau, puis
    on le fait pointer vers son remplaçant. Le tout dans une seule transaction :
    à aucun moment le corpus ne se retrouve sans dérivé pour cette cible, et un
    échec en cours de route ne laisse rien à moitié fait.
    """
    with conn.cursor() as cur:
        cur.execute("""select id from derivative
                        where kind = %s and superseded_by is null
                          and document_id = %s
                          and chapter_id is not distinct from %s""",
                    (kind, doc_id, chapter_id))
        anciens = [r[0] for r in cur.fetchall()]
        if anciens:
            # Marqueur provisoire : l'index n'accepte qu'un actif par cible, il
            # faut donc libérer la place avant d'insérer. Le pointeur définitif
            # est posé juste après, quand l'identifiant du nouveau existe.
            cur.execute("update derivative set superseded_by = id where id = any(%s)", (anciens,))

        cur.execute("""insert into derivative (document_id, chapter_id, kind, level, content,
                         model_id, prompt_version, cost_tokens_in, cost_tokens_out)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
                    (doc_id, chapter_id, kind, level, json.dumps(data, ensure_ascii=False),
                     MODEL, PROMPT_VERSION, usage[0], usage[1]))
        did = cur.fetchone()[0]
        if anciens:
            cur.execute("update derivative set superseded_by = %s where id = any(%s)",
                        (did, anciens))
        if kind == "fiche_lecture":
            cur.execute("""insert into document_pedagogy (document_id, level, doc_type,
                             target_audience, central_thesis, key_ideas)
                           values (%s,%s,%s,%s,%s,%s)
                           on conflict (document_id) do update set
                             level=excluded.level, doc_type=excluded.doc_type,
                             target_audience=excluded.target_audience,
                             central_thesis=excluded.central_thesis, key_ideas=excluded.key_ideas""",
                        (doc_id, data["niveau"], data["type_ouvrage"], data["public_cible"],
                         data["these_centrale"], json.dumps(data["idees_force"], ensure_ascii=False)))
            for c in data["concepts_cles"]:
                cur.execute("""insert into concept (term, definition) values (%s,%s)
                               on conflict (term) do nothing""", (c["terme"], c["definition"]))
    conn.commit()
    return did

# ------------------------------------------------------------------ exécution
def client():
    import anthropic
    return anthropic.Anthropic()

def run_sync(conn, jobs):
    cl = client()
    for j in jobs:
        prompt, used = build_prompt(conn, j["doc_id"], j["kind"], j.get("chapter_id"))
        if not prompt:
            print(f"  (pas de texte) {j['label']}"); continue
        print(f"→ {j['kind']:14s} {j['label'][:56]}  ({used} tok de contexte)", flush=True)
        with cl.messages.stream(
            model=MODEL, max_tokens=32000, system=SYSTEM,
            thinking={"type": "adaptive"},
            output_config={"effort": "high",
                           "format": {"type": "json_schema", "schema": SCHEMAS[j["kind"]]}},
            messages=[{"role": "user", "content": prompt}],
        ) as st:
            msg = st.get_final_message()
        if msg.stop_reason == "refusal":
            print(f"   refus ({msg.stop_details})"); continue
        data = json.loads(next(b.text for b in msg.content if b.type == "text"))
        save(conn, j["doc_id"], j.get("chapter_id"), j["kind"], j.get("level"),
             data, (msg.usage.input_tokens, msg.usage.output_tokens))
        print(f"   OK  in={msg.usage.input_tokens} out={msg.usage.output_tokens}", flush=True)

def run_batch(conn, jobs, out):
    from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
    from anthropic.types.messages.batch_create_params import Request
    cl, reqs, index = client(), [], {}
    for i, j in enumerate(jobs):
        prompt, used = build_prompt(conn, j["doc_id"], j["kind"], j.get("chapter_id"))
        if not prompt:
            continue
        cid = f"{j['kind']}-{i}"
        index[cid] = j
        reqs.append(Request(custom_id=cid, params=MessageCreateParamsNonStreaming(
            model=MODEL, max_tokens=32000, system=SYSTEM,
            thinking={"type": "adaptive"},
            output_config={"effort": "high",
                           "format": {"type": "json_schema", "schema": SCHEMAS[j["kind"]]}},
            messages=[{"role": "user", "content": prompt}])))
    print(f"{len(reqs)} requêtes -> batch (50 % du tarif)")
    b = cl.messages.batches.create(requests=reqs)
    Path(out).write_text(json.dumps({"batch_id": b.id, "index": index}, default=str, ensure_ascii=False))
    print(f"batch {b.id} créé. Récupération : --collect {out}")

def collect(conn, state_file):
    cl = client()
    st = json.loads(Path(state_file).read_text())
    bid, index = st["batch_id"], st["index"]
    while True:
        b = cl.messages.batches.retrieve(bid)
        if b.processing_status == "ended":
            break
        print(f"  {b.processing_status} : {b.request_counts.processing} en cours", flush=True)
        time.sleep(60)
    ok = err = 0
    for r in cl.messages.batches.results(bid):
        j = index.get(r.custom_id)
        if r.result.type != "succeeded" or not j:
            err += 1; continue
        m = r.result.message
        if m.stop_reason == "refusal":
            err += 1; continue
        data = json.loads(next(x.text for x in m.content if x.type == "text"))
        save(conn, j["doc_id"], j.get("chapter_id"), j["kind"], j.get("level"),
             data, (m.usage.input_tokens, m.usage.output_tokens))
        ok += 1
    print(f"{ok} dérivés enregistrés, {err} échecs")

# ------------------------------------------------------------------ sélection
# Ce qui se produit une fois par ouvrage. Le reste se produit par chapitre.
PAR_OUVRAGE = {"fiche_lecture", "synthese", "resume_executif"}

# En deçà, un chapitre est de l'appareil : sommaire, colophon, index, quatrième
# de couverture. Le planificateur ne les programme jamais en séance ; produire
# un quiz dessus, c'est payer pour un contenu que personne ne verra. Le seuil
# est celui du planificateur et de `pipeline/livre/etat.py` : les trois vues du
# corpus doivent compter la même chose, sinon un ouvrage n'atteint jamais
# l'état « complet ».
TOKENS_MIN_CHAPITRE = 300


def pick_jobs(conn, kinds, limit=0, only=None, doc=None, refaire=False):
    """Les dérivés qui restent à produire.

    Sans `refaire`, ce qui existe déjà est écarté. C'était le défaut le plus
    coûteux du module : la sélection ne regardait jamais la table `derivative`,
    et relancer pour combler les quiz manquants aurait régénéré les deux mille
    trois cents déjà produits, au tarif plein.
    """
    jobs = []
    with conn.cursor() as cur:
        cur.execute("""select d.id, d.title_clean from document d
                       where d.ocr_status in ('none','done') and d.has_text_layer
                         and d.takedown_status = 'none'
                       order by d.page_count desc""")
        docs = cur.fetchall()
    if only:
        docs = [d for d in docs if only.lower() in (d[1] or "").lower()]
    if doc:
        # Préfixe d'identifiant, comme le passe le module par ouvrage.
        docs = [d for d in docs if str(d[0]).startswith(doc)]
    if limit:
        docs = docs[:limit]

    for doc_id, title in docs:
        for k in kinds:
            if k in PAR_OUVRAGE:
                if not refaire and _existe(conn, doc_id, None, k):
                    continue
                jobs.append(dict(doc_id=doc_id, kind=k, label=title,
                                 level="intermediaire" if k == "synthese" else None))
            else:
                with conn.cursor() as cur:
                    cur.execute("""select c.id, c.title from chapter c
                                   where c.document_id=%s
                                     and coalesce(c.token_count,0) >= %s
                                     and exists (select 1 from chunk k where k.chapter_id=c.id)
                                   order by c.ord""", (doc_id, TOKENS_MIN_CHAPITRE))
                    chapitres = cur.fetchall()
                for ch_id, ch_title in chapitres:
                    if not refaire and _existe(conn, doc_id, ch_id, k):
                        continue
                    jobs.append(dict(doc_id=doc_id, chapter_id=ch_id, kind=k,
                                     label=f"{title} / {ch_title}"))
    return jobs


def _existe(conn, doc_id, chapter_id, kind) -> bool:
    with conn.cursor() as cur:
        cur.execute("""select 1 from derivative
                        where kind = %s and superseded_by is null
                          and document_id = %s
                          and chapter_id is not distinct from %s
                        limit 1""", (kind, doc_id, chapter_id))
        return cur.fetchone() is not None


def estimer(conn, jobs) -> None:
    """Ce que la campagne va coûter, avant de la lancer.

    Les jetons d'entrée sont comptés exactement : le contexte est assemblé de
    la même façon qu'à l'exécution. Ceux de sortie sont estimés, faute de
    savoir à l'avance ce que le modèle écrira.
    """
    entree = 0
    vides = 0
    for j in jobs:
        _, used = build_prompt(conn, j["doc_id"], j["kind"], j.get("chapter_id"))
        if not used:
            vides += 1
        entree += used
    sortie = len(jobs) * SORTIE_ESTIMEE
    prix = entree / 1e6 * TARIF_ENTREE + sortie / 1e6 * TARIF_SORTIE
    print(f"\n{len(jobs)} dérivés à produire" + (f", dont {vides} sans texte exploitable" if vides else ""))
    print(f"  entrée  {entree:>12,} jetons (comptés)".replace(",", " "))
    print(f"  sortie  {sortie:>12,} jetons (estimés à {SORTIE_ESTIMEE} par dérivé)".replace(",", " "))
    print(f"\n  en direct  environ {prix:8.2f} $")
    print(f"  en batch   environ {prix / 2:8.2f} $  (moitié du tarif, moins de 24 h)")
    print(f"\n  Tarifs appliqués : {TARIF_ENTREE} $ et {TARIF_SORTIE} $ par million de jetons.")
    print("  À vérifier chez Anthropic avant de s'engager sur un budget.")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kinds", default="fiche_lecture")
    # Alias au singulier : c'est ainsi que le module par ouvrage appelle, et
    # l'absence de cet alias faisait échouer la chaîne entière avant le premier
    # appel au modèle.
    ap.add_argument("--kind", dest="kinds")
    ap.add_argument("--doc", help="préfixe d'identifiant d'ouvrage")
    ap.add_argument("--refaire", action="store_true",
                    help="régénère même ce qui existe déjà")
    ap.add_argument("--estimer", action="store_true",
                    help="chiffre la campagne sans rien produire")
    ap.add_argument("--sync", action="store_true")
    ap.add_argument("--batch", action="store_true")
    ap.add_argument("--collect")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--only")
    ap.add_argument("--state", default=str(ROOT / "data/derivatives/batch.json"))
    a = ap.parse_args()
    conn = pg()
    if a.collect:
        return collect(conn, a.collect)
    jobs = pick_jobs(conn, a.kinds.split(","), a.limit, a.only, a.doc, a.refaire)
    if a.estimer:
        return estimer(conn, jobs)
    print(f"{len(jobs)} dérivés à produire")
    if not jobs:
        return
    if a.sync:
        run_sync(conn, jobs)
    elif a.batch:
        Path(a.state).parent.mkdir(parents=True, exist_ok=True)
        run_batch(conn, jobs, a.state)
    else:
        for j in jobs[:20]:
            print(" ", j["kind"], "|", j["label"][:70])

if __name__ == "__main__":
    main()
