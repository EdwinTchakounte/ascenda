namespace Ascenda.Noyau.Modeles;

public sealed record Acces(bool Complet, IReadOnlyList<string> Fonctions, string Source,
                           DateTimeOffset? JusquAu);

public sealed record Utilisateur(string Id, string Email, string? Nom, string Plan, Acces Acces)
{
    public bool ADroit(string fonction) =>
        Acces.Complet || Acces.Fonctions.Contains(fonction);

    public string Prenom => Nom?.Split(' ').FirstOrDefault() ?? "lecteur";
}

public sealed record Jetons(string Acces, string Rafraichissement);

public sealed record Session(Utilisateur? Utilisateur, Jetons? Jetons)
{
    public static readonly Session Vide = new(null, null);
    public bool Connecte => Utilisateur is not null && Jetons is not null;
}
