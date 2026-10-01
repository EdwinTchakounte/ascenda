namespace Ascenda.Noyau.Navigation;

public interface INavigateur
{
    Task AllerAsync(string route, IDictionary<string, object>? parametres = null);
    Task RevenirAsync();
    Task AvertirAsync(string message);
}

public sealed class NavigateurMuet : INavigateur
{
    public List<string> Routes { get; } = new();
    public List<string> Avertissements { get; } = new();
    public int Retours { get; private set; }

    public Task AllerAsync(string route, IDictionary<string, object>? parametres = null)
    {
        Routes.Add(route);
        return Task.CompletedTask;
    }

    public Task RevenirAsync()
    {
        Retours++;
        return Task.CompletedTask;
    }

    public Task AvertirAsync(string message)
    {
        Avertissements.Add(message);
        return Task.CompletedTask;
    }
}
