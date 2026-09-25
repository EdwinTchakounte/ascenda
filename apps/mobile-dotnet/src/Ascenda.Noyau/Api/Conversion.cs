using Ascenda.Noyau.Modeles;

namespace Ascenda.Noyau.Api;

public static class Conversion
{
    public static Acces Vers(this AccesDto? d) => d is null
        ? new Acces(false, Array.Empty<string>(), "aucun", null)
        : new Acces(d.Complet, d.Fonctions, d.Source, d.JusquAu);

    public static Utilisateur? Vers(this UtilisateurDto? d) => d is null
        ? null
        : new Utilisateur(d.Id, d.Email, d.Nom, d.Plan, d.Acces.Vers());

    public static Ouvrage Vers(this OuvrageDto d) =>
        new(d.Id, d.Titre, d.Auteurs, d.Annee, d.Pages, d.Niveau, d.DureeMin, d.AxeSlug,
            d.These, d.AQuiz, d.LectureIntegrale);

    public static Chapitre Vers(this ChapitreDto d) =>
        new(d.Id, d.Titre, d.Ordre, d.PageDebut, d.PageFin, d.DureeMin, d.Texte);

    public static EtatSeance EtatDepuis(string statut) => statut switch
    {
        "fait" => EtatSeance.Faite,
        "saute" => EtatSeance.Sautee,
        "en_retard" => EtatSeance.EnRetard,
        _ => EtatSeance.AVenir,
    };

    public static Seance Vers(this SeanceDto d) =>
        new(d.Id, d.Ordre, d.DocumentId, d.Ouvrage, d.ChapitreId, d.Chapitre, d.PageDebut,
            d.PageFin, d.PrevueLe, d.DureeMin, d.Livrable, d.LivrableId, EtatDepuis(d.Statut));

    public static Chronogramme Vers(this ChronogrammeDto d)
    {
        var seances = d.Seances.Select(Vers).ToList();
        var faites = d.Faites > 0 ? d.Faites : seances.Count(s => s.Etat == EtatSeance.Faite);
        var total = d.Total > 0 ? d.Total : seances.Count;
        return new Chronogramme(d.Id, d.AxeSlug, d.AxeLabel, d.Resume ?? "", total, faites, seances);
    }

    public static Journee Vers(this JourneeDto d) =>
        new(d.Seance?.Vers(),
            d.Semaine.Select(j => new JourSemaine(
                DateOnly.TryParse(j.Jour, out var jour) ? jour : default,
                EtatDepuis(j.Statut), j.Nombre)).ToList(),
            d.NotionsAReviser);

    public static Quiz Vers(this QuizDto d) =>
        new(d.Id, d.ChapitreId, d.Chapitre,
            d.Questions.Select(q => new Question(q.Index, q.Enonce, q.Choix, q.Page, q.Niveau))
                       .ToList());

    public static Correction Vers(this CorrectionDto d)
    {
        var verdicts = d.Details.Select(x => new Verdict(
            x.Index, x.Juste, x.VotreReponse ?? -1, x.BonneReponse, x.Explication,
            x.Extrait?.Texte, x.Extrait?.Page ?? x.Page)).ToList();
        var total = d.Total > 0 ? d.Total : verdicts.Count;
        var justes = d.Justes > 0 ? d.Justes : verdicts.Count(v => v.Juste);
        return new Correction(justes, total, verdicts);
    }

    public static Progression Vers(this ProgressionDto d) =>
        new(d.Seances.Total, d.Seances.Faites, d.Seances.MinutesLues, d.Quiz.Tentatives,
            d.Quiz.ScoreMoyen, d.Ouvrages.Termines, d.Notions.Suivies, d.Notions.ARevoir);
}
