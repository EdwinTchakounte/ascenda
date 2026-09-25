using System.Text.Json.Serialization;

namespace Ascenda.Noyau.Api;

public sealed class AccesDto
{
    [JsonPropertyName("complet")] public bool Complet { get; set; }
    [JsonPropertyName("fonctions")] public List<string> Fonctions { get; set; } = new();
    [JsonPropertyName("source")] public string Source { get; set; } = "aucun";
    [JsonPropertyName("jusqu_au")] public DateTimeOffset? JusquAu { get; set; }
}

public sealed class UtilisateurDto
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("email")] public string Email { get; set; } = "";
    [JsonPropertyName("nom")] public string? Nom { get; set; }
    [JsonPropertyName("plan")] public string Plan { get; set; } = "free";
    [JsonPropertyName("acces")] public AccesDto? Acces { get; set; }
}

public sealed class JetonsDto
{
    [JsonPropertyName("access_token")] public string Acces { get; set; } = "";
    [JsonPropertyName("refresh_token")] public string Rafraichissement { get; set; } = "";
}

public sealed class SessionDto
{
    [JsonPropertyName("jetons")] public JetonsDto? Jetons { get; set; }
    [JsonPropertyName("utilisateur")] public UtilisateurDto? Utilisateur { get; set; }
    [JsonPropertyName("message_code")] public string? MessageCode { get; set; }
}

public sealed class OuvrageDto
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("titre")] public string Titre { get; set; } = "";
    [JsonPropertyName("auteurs")] public List<string> Auteurs { get; set; } = new();
    [JsonPropertyName("annee")] public int? Annee { get; set; }
    [JsonPropertyName("pages")] public int Pages { get; set; }
    [JsonPropertyName("niveau")] public string Niveau { get; set; } = "intermediaire";
    [JsonPropertyName("duree_min")] public int DureeMin { get; set; }
    [JsonPropertyName("axe_slug")] public string? AxeSlug { get; set; }
    [JsonPropertyName("these")] public string? These { get; set; }
    [JsonPropertyName("a_quiz")] public bool AQuiz { get; set; }
    [JsonPropertyName("lecture_integrale")] public bool LectureIntegrale { get; set; }
}

public sealed class BibliothequeDto
{
    [JsonPropertyName("total")] public int Total { get; set; }
    [JsonPropertyName("page")] public int Page { get; set; }
    [JsonPropertyName("ouvrages")] public List<OuvrageDto> Ouvrages { get; set; } = new();
}

public sealed class ChapitreDto
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("titre")] public string Titre { get; set; } = "";
    [JsonPropertyName("ordre")] public int Ordre { get; set; }
    [JsonPropertyName("page_debut")] public int PageDebut { get; set; }
    [JsonPropertyName("page_fin")] public int PageFin { get; set; }
    [JsonPropertyName("duree_min")] public int DureeMin { get; set; }
    [JsonPropertyName("texte")] public string? Texte { get; set; }
}

public sealed class SeanceDto
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("ordre")] public int Ordre { get; set; }
    [JsonPropertyName("document_id")] public string DocumentId { get; set; } = "";
    [JsonPropertyName("ouvrage")] public string Ouvrage { get; set; } = "";
    [JsonPropertyName("chapitre_id")] public string? ChapitreId { get; set; }
    [JsonPropertyName("chapitre")] public string? Chapitre { get; set; }
    [JsonPropertyName("page_debut")] public int PageDebut { get; set; }
    [JsonPropertyName("page_fin")] public int PageFin { get; set; }
    [JsonPropertyName("prevue_le")] public DateTimeOffset PrevueLe { get; set; }
    [JsonPropertyName("duree_min")] public int DureeMin { get; set; }
    [JsonPropertyName("livrable")] public string Livrable { get; set; } = "quiz";
    [JsonPropertyName("livrable_id")] public string? LivrableId { get; set; }
    [JsonPropertyName("statut")] public string Statut { get; set; } = "a_venir";
}

public sealed class ChronogrammeDto
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("axe")] public string AxeSlug { get; set; } = "";
    [JsonPropertyName("axe_label")] public string AxeLabel { get; set; } = "";
    [JsonPropertyName("resume")] public string? Resume { get; set; }
    [JsonPropertyName("total")] public int Total { get; set; }
    [JsonPropertyName("faites")] public int Faites { get; set; }
    [JsonPropertyName("seances")] public List<SeanceDto> Seances { get; set; } = new();
}

public sealed class JourSemaineDto
{
    [JsonPropertyName("jour")] public string Jour { get; set; } = "";
    [JsonPropertyName("statut")] public string Statut { get; set; } = "a_venir";
    [JsonPropertyName("nb")] public int Nombre { get; set; }
}

public sealed class JourneeDto
{
    [JsonPropertyName("seance")] public SeanceDto? Seance { get; set; }
    [JsonPropertyName("semaine")] public List<JourSemaineDto> Semaine { get; set; } = new();
    [JsonPropertyName("notions_a_reviser")] public int NotionsAReviser { get; set; }
}

public sealed class QuestionDto
{
    [JsonPropertyName("index")] public int Index { get; set; }
    [JsonPropertyName("q")] public string Enonce { get; set; } = "";
    [JsonPropertyName("choix")] public List<string> Choix { get; set; } = new();
    [JsonPropertyName("page")] public int? Page { get; set; }
    [JsonPropertyName("niveau")] public string? Niveau { get; set; }
}

public sealed class QuizDto
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("chapitre_id")] public string? ChapitreId { get; set; }
    [JsonPropertyName("chapitre")] public string? Chapitre { get; set; }
    [JsonPropertyName("questions")] public List<QuestionDto> Questions { get; set; } = new();
}

public sealed class ExtraitDto
{
    [JsonPropertyName("texte")] public string? Texte { get; set; }
    [JsonPropertyName("page")] public int? Page { get; set; }
}

public sealed class DetailDto
{
    [JsonPropertyName("index")] public int Index { get; set; }
    [JsonPropertyName("juste")] public bool Juste { get; set; }
    [JsonPropertyName("votre_reponse")] public int? VotreReponse { get; set; }
    [JsonPropertyName("bonne_reponse")] public int BonneReponse { get; set; }
    [JsonPropertyName("explication")] public string? Explication { get; set; }
    [JsonPropertyName("page")] public int? Page { get; set; }
    [JsonPropertyName("extrait")] public ExtraitDto? Extrait { get; set; }
}

public sealed class CorrectionDto
{
    [JsonPropertyName("score")] public double Score { get; set; }
    [JsonPropertyName("justes")] public int Justes { get; set; }
    [JsonPropertyName("total")] public int Total { get; set; }
    [JsonPropertyName("details")] public List<DetailDto> Details { get; set; } = new();
}

public sealed class ProgressionDto
{
    [JsonPropertyName("seances")] public BlocSeances Seances { get; set; } = new();
    [JsonPropertyName("quiz")] public BlocQuiz Quiz { get; set; } = new();
    [JsonPropertyName("ouvrages")] public BlocOuvrages Ouvrages { get; set; } = new();
    [JsonPropertyName("notions")] public BlocNotions Notions { get; set; } = new();

    public sealed class BlocSeances
    {
        [JsonPropertyName("total")] public int Total { get; set; }
        [JsonPropertyName("faites")] public int Faites { get; set; }
        [JsonPropertyName("minutes_lues")] public int MinutesLues { get; set; }
    }

    public sealed class BlocQuiz
    {
        [JsonPropertyName("tentatives")] public int Tentatives { get; set; }
        [JsonPropertyName("score_moyen")] public double ScoreMoyen { get; set; }
    }

    public sealed class BlocOuvrages
    {
        [JsonPropertyName("termines")] public int Termines { get; set; }
    }

    public sealed class BlocNotions
    {
        [JsonPropertyName("suivies")] public int Suivies { get; set; }
        [JsonPropertyName("a_revoir")] public int ARevoir { get; set; }
    }
}
