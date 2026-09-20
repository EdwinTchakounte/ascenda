namespace Ascenda.Noyau.Modeles;

public enum EtatSeance { AVenir, Faite, Sautee, EnRetard }

public sealed record Seance(string Id, int Ordre, string DocumentId, string Ouvrage,
                            string? ChapitreId, string? Chapitre, int PageDebut, int PageFin,
                            DateTimeOffset PrevueLe, int DureeMin, string Livrable,
                            string? LivrableId, EtatSeance Etat)
{
    public string Pages => $"p. {PageDebut} à {PageFin}";

    public bool EnRetard(DateTimeOffset maintenant) =>
        Etat == EtatSeance.AVenir && PrevueLe.Date < maintenant.Date;
}

public sealed record Chronogramme(string Id, string AxeSlug, string AxeLabel, string Resume,
                                  int Total, int Faites, IReadOnlyList<Seance> Seances)
{
    public double Avancement => Total == 0 ? 0 : (double)Faites / Total;

    public int EnRetard(DateTimeOffset maintenant) => Seances.Count(s => s.EnRetard(maintenant));
}

public sealed record Journee(Seance? Seance, IReadOnlyList<JourSemaine> Semaine,
                             int NotionsARevoir);

public sealed record JourSemaine(DateOnly Jour, EtatSeance Etat, int Nombre)
{
    private static readonly string[] Initiales = { "L", "M", "M", "J", "V", "S", "D" };

    public string Initiale => Initiales[((int)Jour.DayOfWeek + 6) % 7];

    public string Quantieme => Jour.Day.ToString();

    public string Teinte => Etat switch
    {
        EtatSeance.Faite => "#D4A23F",
        EtatSeance.Sautee => "#EFEADF",
        _ => "#FFFFFF",
    };
}

public sealed record Progression(int Total, int Faites, int MinutesLues, int Tentatives,
                                 double ScoreMoyen, int OuvragesTermines, int NotionsSuivies,
                                 int NotionsARevoir)
{
    public double Avancement => Total == 0 ? 0 : (double)Faites / Total;

    public string HeuresLues => Duree.EnHeures(MinutesLues);
}
