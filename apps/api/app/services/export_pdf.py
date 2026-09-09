"""Export PDF d'un pack d'ouvrage.

Un document qu'on imprime, qu'on partage, qu'on emporte dans une salle sans
réseau. Il reprend la fiche, les idées-force, le plan de lecture, les citations
avec leurs pages et les quiz avec leur corrigé.

Écrit avec fpdf2 : deux cents kilo-octets de dépendance, aucune bibliothèque
système. Sur une machine où l'installation d'un paquet prend des minutes, cela
compte.
"""
import io
import unicodedata

from fpdf import FPDF

from app.services.droits import tronquer

OR = (154, 113, 24)
ENCRE = (26, 31, 46)
GRIS = (107, 114, 128)
NUIT = (11, 20, 53)


def _latin1(texte: str | None) -> str:
    """Les polices de base de fpdf2 sont en Latin-1.

    Plutôt que d'embarquer une police Unicode de plusieurs mégaoctets, on
    translittère ce qui ne passe pas. Les accents français passent ; les
    guillemets typographiques et les tirets longs sont ramenés à leur
    équivalent simple.
    """
    if not texte:
        return ""
    remplacements = {
        "’": "'", "‘": "'", "“": '"', "”": '"',
        "–": "-", "—": "-", "…": "...", " ": " ",
        " ": " ", "‹": "<", "›": ">", "œ": "oe", "Œ": "OE",
    }
    for a, b in remplacements.items():
        texte = texte.replace(a, b)
    try:
        texte.encode("latin-1")
        return texte
    except UnicodeEncodeError:
        return unicodedata.normalize("NFKD", texte).encode("latin-1", "ignore").decode("latin-1")


class Document(FPDF):
    def __init__(self, titre: str):
        super().__init__(format="A4")
        self.titre_ouvrage = titre
        self.set_auto_page_break(auto=True, margin=18)
        self.set_margins(20, 18, 20)

    def header(self):
        if self.page_no() == 1:
            return
        self.set_font("Helvetica", "", 8)
        self.set_text_color(*GRIS)
        self.cell(0, 6, _latin1(self.titre_ouvrage)[:70], align="L")
        self.cell(0, 6, "ASCENDA", align="R")
        self.ln(9)

    def footer(self):
        self.set_y(-14)
        self.set_font("Helvetica", "", 8)
        self.set_text_color(*GRIS)
        self.cell(0, 6, f"{self.page_no()}", align="C")

    # -- aides de mise en page

    def bloc(self, texte: str, hauteur: float):
        """multi_cell en repartant systematiquement de la marge gauche.

        fpdf laisse le curseur ou le bloc precedent s'est arrete. Sans remise a
        la marge, la largeur disponible finit par tomber a zero et le rendu
        echoue au milieu du document.
        """
        self.set_x(self.l_margin)
        self.multi_cell(0, hauteur, texte)

    def titre(self, texte: str, taille: int = 16, espace: int = 4):
        self.set_font("Helvetica", "B", taille)
        self.set_text_color(*NUIT)
        self.bloc(_latin1(texte), taille * 0.5)
        self.ln(espace)

    def oeil(self, texte: str):
        self.set_font("Helvetica", "B", 8)
        self.set_text_color(*OR)
        self.cell(0, 5, _latin1(texte.upper()))
        self.ln(6)

    def paragraphe(self, texte: str, taille: int = 10, gris: bool = False):
        self.set_font("Helvetica", "", taille)
        self.set_text_color(*(GRIS if gris else ENCRE))
        self.bloc(_latin1(texte), taille * 0.52)
        self.ln(2)

    def puce(self, texte: str, numero: int | None = None):
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(*OR)
        marque = f"{numero}." if numero else "-"
        self.set_x(self.l_margin)
        self.cell(7, 5.4, marque)
        self.set_font("Helvetica", "", 10)
        self.set_text_color(*ENCRE)
        # Le retrait laisse la place a la puce sans la chevaucher.
        self.set_x(self.l_margin + 7)
        self.multi_cell(0, 5.4, _latin1(texte))
        self.ln(1)

    def filet(self):
        self.set_draw_color(220, 216, 208)
        self.line(20, self.get_y(), 190, self.get_y())
        self.ln(5)


# Un export complet d'un ouvrage bien fourni fait quarante-trois pages et six
# secondes de rendu : personne n'imprime cela. Par défaut on produit un
# compagnon de lecture d'une dizaine de pages ; l'intégrale reste accessible à
# la demande.
CITATIONS_PAR_DEFAUT = 60
QUESTIONS_PAR_DEFAUT = 60


def produire(pack: dict, complet: bool = False) -> bytes:
    o = pack["ouvrage"]
    pdf = Document(o["titre"])
    pdf.add_page()

    # --- page de titre
    pdf.ln(16)
    pdf.oeil("ASCENDA, lecture guidee")
    pdf.titre(o["titre"], 22, 2)
    if o.get("sous_titre"):
        pdf.paragraphe(o["sous_titre"], 12, gris=True)
    pdf.ln(2)
    meta = " | ".join(
        x for x in [
            ", ".join(o["auteurs"][:3]) if o["auteurs"] else None,
            str(o["annee"]) if o.get("annee") else None,
            o.get("editeur") or None,
            f"{o['pages']} pages" if o.get("pages") else None,
        ] if x
    )
    if meta:
        pdf.paragraphe(meta, 9, gris=True)
    if o["axes"]:
        pdf.paragraphe(" - ".join(a["label"] for a in o["axes"]), 9, gris=True)
    pdf.ln(4)
    pdf.filet()

    if pack["droits"].get("message"):
        pdf.paragraphe(pack["droits"]["message"], 8.5, gris=True)
        pdf.ln(2)

    # --- thèse et idées-force
    if o.get("these_centrale"):
        pdf.oeil("These centrale")
        pdf.paragraphe(o["these_centrale"], 11)
        pdf.ln(3)

    idees = o.get("idees_force") or []
    if idees:
        pdf.oeil("Idees-force")
        for i, idee in enumerate(idees, 1):
            texte = idee if isinstance(idee, str) else (
                idee.get("idee") or idee.get("titre") or str(idee))
            pdf.puce(texte, i)
        pdf.ln(3)

    # --- plan de lecture
    sommaire = pack.get("sommaire") or []
    if sommaire:
        pdf.add_page()
        pdf.oeil("Plan de lecture")
        pdf.titre("Sommaire", 15)
        for c in sommaire:
            pdf.set_font("Helvetica", "", 10)
            pdf.set_text_color(*ENCRE)
            titre = _latin1(c["titre"] or f"Chapitre {c['ordre']}")[:78]
            detail = " | ".join(x for x in [
                f"p. {c['page_debut']}" if c.get("page_debut") else None,
                f"{c['duree_min']} min" if c.get("duree_min") else None,
            ] if x)
            pdf.cell(140, 5.6, titre)
            pdf.set_text_color(*GRIS)
            pdf.cell(0, 5.6, detail, align="R")
            pdf.ln(5.6)
        pdf.ln(3)

    # --- citations
    toutes_citations = pack.get("citations") or []
    citations = toutes_citations if complet else toutes_citations[:CITATIONS_PAR_DEFAUT]
    if citations:
        pdf.add_page()
        pdf.oeil(f"{len(citations)} citations verifiees"
                 + ("" if complet or len(citations) == len(toutes_citations)
                    else f" sur {len(toutes_citations)}"))
        pdf.titre("Ce que le livre dit, mot pour mot", 15)
        pdf.paragraphe(
            "Chaque citation a ete verifiee caractere par caractere contre le "
            "texte source, et porte sa page.", 9, gris=True)
        pdf.ln(3)
        for c in citations:
            texte, _ = tronquer(c.get("texte") or "", 700)
            pdf.set_font("Helvetica", "I", 10)
            pdf.set_text_color(*ENCRE)
            pdf.bloc(_latin1(f'"{texte}"'), 5.2)
            pdf.set_font("Helvetica", "", 8.5)
            pdf.set_text_color(*OR)
            ligne = " - ".join(x for x in [
                f"p. {c['page']}" if c.get("page") else None, c.get("theme")] if x)
            pdf.bloc(_latin1(ligne), 4.4)
            if c.get("portee"):
                pdf.set_text_color(*GRIS)
                pdf.set_font("Helvetica", "", 8.5)
                pdf.bloc(_latin1(c["portee"]), 4.4)
            pdf.ln(3)

    # --- quiz et corrigé
    quiz = pack.get("quiz") or []
    if not complet:
        # On garde les premiers lots jusqu'au plafond, plutôt que de couper au
        # milieu d'un chapitre : un quiz tronqué n'a pas de sens.
        retenus, compte = [], 0
        for lot in quiz:
            if compte and compte + len(lot["questions"]) > QUESTIONS_PAR_DEFAUT:
                break
            retenus.append(lot)
            compte += len(lot["questions"])
        quiz = retenus
    posees = sum(len(lot["questions"]) for lot in quiz)
    total_questions = pack["compteurs"]["questions"]
    if quiz:
        pdf.add_page()
        pdf.oeil(f"{posees} questions"
                 + ("" if posees == total_questions else f" sur {total_questions}"))
        pdf.titre("Quiz", 15)
        for lot in quiz:
            if lot.get("chapitre"):
                pdf.set_font("Helvetica", "B", 10.5)
                pdf.set_text_color(*NUIT)
                pdf.bloc(_latin1(lot["chapitre"]), 5.4)
                pdf.ln(1)
            for q in lot["questions"]:
                pdf.set_font("Helvetica", "B", 10)
                pdf.set_text_color(*ENCRE)
                pdf.bloc(_latin1(q["question"]), 5.2)
                for i, choix in enumerate(q.get("choix", [])):
                    juste = q.get("reponse") == i
                    pdf.set_font("Helvetica", "B" if juste else "", 9.5)
                    pdf.set_text_color(*(OR if juste else GRIS))
                    pdf.bloc(_latin1(f"   {chr(97 + i)}. {choix}"), 4.8)
                if q.get("explication"):
                    pdf.set_font("Helvetica", "I", 8.5)
                    pdf.set_text_color(*GRIS)
                    pdf.bloc(_latin1(f"   {q['explication']}"), 4.4)
                pdf.ln(3)

    if not complet and (len(citations) < len(toutes_citations) or posees < total_questions):
        pdf.ln(6)
        pdf.filet()
        pdf.paragraphe(
            f"Ce document reprend {len(citations)} des {len(toutes_citations)} citations "
            f"et {posees} des {total_questions} questions de l'ouvrage. "
            f"L'integralite est disponible dans l'application, et en PDF sur demande.",
            8.5, gris=True)

    sortie = io.BytesIO()
    pdf.output(sortie)
    return sortie.getvalue()
