namespace Ascenda.Noyau.Modeles;

public sealed record Ouvrage(string Id, string Titre, IReadOnlyList<string> Auteurs, int? Annee,
                             int Pages, string Niveau, int DureeMin, string? AxeSlug,
                             string? These, bool AQuiz, bool LectureIntegrale)
{
    public string Signature => Auteurs.Count == 0 ? "auteur inconnu" : string.Join(", ", Auteurs);

    public string DureeLisible => Duree.EnHeures(DureeMin);

    public string Resume => $"{Niveau} · {DureeLisible} de lecture · {Pages} pages";
}

public sealed record Chapitre(string Id, string Titre, int Ordre, int PageDebut, int PageFin,
                              int DureeMin, string? Texte);

public sealed record Axe(string Slug, string Label, int NbOuvrages, int NbPages, int DureeMin,
                         bool Reserve, string? Pole);

public sealed record Notion(string Id, string Terme, string? Definition, int NbPassages);

public sealed record Passage(string DocumentId, string Ouvrage, string? Chapitre, int Page,
                             string Extrait);

public static class Duree
{
    public static string EnHeures(int minutes)
    {
        if (minutes < 60) return $"{minutes} min";
        var h = minutes / 60;
        var reste = minutes % 60;
        return reste == 0 ? $"{h} h" : $"{h} h {reste:00}";
    }
}
