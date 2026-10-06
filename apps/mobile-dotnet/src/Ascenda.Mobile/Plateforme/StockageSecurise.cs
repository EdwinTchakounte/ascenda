using Ascenda.Noyau.Api;

namespace Ascenda.Mobile.Plateforme;

public sealed class StockageSecurise : IStockage
{
    public async Task<string?> LireAsync(string cle)
    {
        try
        {
            return await SecureStorage.Default.GetAsync(cle);
        }
        catch (Exception)
        {
            return null;
        }
    }

    public Task EcrireAsync(string cle, string valeur) => SecureStorage.Default.SetAsync(cle, valeur);

    public Task EffacerAsync(string cle)
    {
        SecureStorage.Default.Remove(cle);
        return Task.CompletedTask;
    }
}
