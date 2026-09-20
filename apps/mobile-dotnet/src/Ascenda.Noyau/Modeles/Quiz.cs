namespace Ascenda.Noyau.Modeles;

public sealed record Question(int Index, string Enonce, IReadOnlyList<string> Choix, int? Page,
                              string? Niveau);

public sealed record Quiz(string Id, string? ChapitreId, string? Chapitre,
                          IReadOnlyList<Question> Questions)
{
    public int Nombre => Questions.Count;
}

public sealed record Verdict(int Index, bool Juste, int Donnee, int Attendue,
                             string? Explication, string? Citation, int? Page)
{
    public string Marque => Juste ? "JUSTE" : "À REVOIR";
}

public sealed record Correction(int Justes, int Total, IReadOnlyList<Verdict> Verdicts)
{
    public double Score => Total == 0 ? 0 : (double)Justes / Total;

    public string Mention => Score switch
    {
        >= 0.9 => "Acquis",
        >= 0.7 => "Presque",
        >= 0.5 => "À retravailler",
        _ => "À reprendre",
    };
}
