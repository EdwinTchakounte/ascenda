using Ascenda.Noyau.Navigation;

namespace Ascenda.Mobile.Plateforme;

public sealed class NavigateurShell : INavigateur
{
    public Task AllerAsync(string route, IDictionary<string, object>? parametres = null) =>
        parametres is null
            ? Shell.Current.GoToAsync(route)
            : Shell.Current.GoToAsync(route, parametres);

    public Task RevenirAsync() => Shell.Current.GoToAsync("..");

    public Task AvertirAsync(string message) =>
        Shell.Current.DisplayAlert("Ascenda", message, "Entendu");
}
