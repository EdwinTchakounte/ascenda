namespace Ascenda.Noyau.Modeles;

public sealed record Source(string Ouvrage, string? Chapitre, int? Page, string Extrait)
{
    public string Reference => Page is null ? Ouvrage : $"{Ouvrage}, p. {Page}";
}

public sealed record Echange(string Role, string Texte, IReadOnlyList<Source> Sources,
                             bool Degrade = false)
{
    public bool DeMoi => Role == "user";

    public string Auteur => DeMoi ? "VOTRE QUESTION" : "L'AGENT";

    public string Teinte => DeMoi ? "#EFEADF" : "#FFFFFF";

    public bool ASources => Sources.Count > 0;

    public string Resume => Sources.Count == 0
        ? ""
        : string.Join("  ·  ", Sources.Take(3).Select(s => s.Reference));
}
