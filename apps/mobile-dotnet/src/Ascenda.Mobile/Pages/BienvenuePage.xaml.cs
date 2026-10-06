namespace Ascenda.Mobile.Pages;

public partial class BienvenuePage : ContentPage
{
    public BienvenuePage() => InitializeComponent();

    private async void SurInscription(object? envoyeur, EventArgs e) =>
        await Shell.Current.GoToAsync("connexion?inscription=1");

    private async void SurConnexion(object? envoyeur, EventArgs e) =>
        await Shell.Current.GoToAsync("connexion");

    private async void SurVisite(object? envoyeur, EventArgs e) =>
        await Shell.Current.GoToAsync("//onglets/livres");
}
