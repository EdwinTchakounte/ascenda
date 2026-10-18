using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Ascenda.Noyau.Modeles;
using Ascenda.Noyau.Navigation;
using Ascenda.Noyau.Services;

namespace Ascenda.Noyau.VuesModeles;

public partial class VmJour : VmBase
{
    private readonly ServiceParcours _parcours;
    private readonly ServiceSession _session;
    private readonly INavigateur _navigateur;

    public VmJour(ServiceParcours parcours, ServiceSession session, INavigateur navigateur)
    {
        _parcours = parcours;
        _session = session;
        _navigateur = navigateur;
    }

    [ObservableProperty] private Seance? _seance;
    [ObservableProperty] private int _notionsARevoir;
    [ObservableProperty] private Progression? _progression;

    public ObservableCollection<JourSemaine> Semaine { get; } = new();

    public string Salutation =>
        $"{Moment()}, {_session.Courante.Utilisateur?.Prenom ?? "lecteur"}";

    public static string Moment(int? heure = null)
    {
        var h = heure ?? DateTime.Now.Hour;
        return h < 12 ? "Bonjour" : h < 18 ? "Bon après-midi" : "Bonsoir";
    }

    public bool RienAFaire => !Occupe && Seance is null && !EnEchec;

    public bool ARevoir => NotionsARevoir > 0;

    public string Quantieme => DateTime.Now.ToString("dddd d MMMM",
        new System.Globalization.CultureInfo("fr-FR")).ToUpperInvariant();

    [RelayCommand]
    public async Task ChargerAsync()
    {
        await TenterAsync(async () =>
        {
            var journee = await _parcours.JourneeAsync();
            Seance = journee?.Seance;
            NotionsARevoir = journee?.NotionsARevoir ?? 0;
            Semaine.Clear();
            foreach (var j in journee?.Semaine ?? Array.Empty<JourSemaine>())
                Semaine.Add(j);
            Progression = await _parcours.ProgressionAsync();
        });
        OnPropertyChanged(nameof(Salutation));
        OnPropertyChanged(nameof(RienAFaire));
        OnPropertyChanged(nameof(ARevoir));
    }

    [RelayCommand]
    private async Task OuvrirAsync()
    {
        if (Seance is null) return;
        await _navigateur.AllerAsync("lecteur", new Dictionary<string, object>
        {
            ["document"] = Seance.DocumentId,
            ["chapitre"] = Seance.ChapitreId ?? "",
            ["seance"] = Seance.Id,
        });
    }
}
