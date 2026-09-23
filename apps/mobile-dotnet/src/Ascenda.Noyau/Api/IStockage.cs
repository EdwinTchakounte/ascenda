namespace Ascenda.Noyau.Api;

public interface IStockage
{
    Task<string?> LireAsync(string cle);
    Task EcrireAsync(string cle, string valeur);
    Task EffacerAsync(string cle);
}

public sealed class StockageMemoire : IStockage
{
    private readonly Dictionary<string, string> _valeurs = new();

    public Task<string?> LireAsync(string cle) =>
        Task.FromResult(_valeurs.TryGetValue(cle, out var v) ? v : null);

    public Task EcrireAsync(string cle, string valeur)
    {
        _valeurs[cle] = valeur;
        return Task.CompletedTask;
    }

    public Task EffacerAsync(string cle)
    {
        _valeurs.Remove(cle);
        return Task.CompletedTask;
    }
}
