using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Ascenda.Noyau.Modeles;
using Ascenda.Noyau.Navigation;
using Ascenda.Noyau.Services;

namespace Ascenda.Noyau.VuesModeles;

public partial class VmBibliotheque : VmBase
{
    private readonly ServiceCorpus _corpus;
    private readonly INavigateur _navigateur;

    public VmBibliotheque(ServiceCorpus corpus, INavigateur navigateur)
    {
        _corpus = corpus;
        _navigateur = navigateur;
        Titre = "Bibliothèque";
    }

    [ObservableProperty] private string? _axe;
    [ObservableProperty] private int _total;
    [ObservableProperty] private string _recherche = "";

    public ObservableCollection<Ouvrage> Ouvrages { get; } = new();

    public string Compteur => $"{Ouvrages.Count} sur {Total} ouvrages";

    [RelayCommand]
    public async Task ChargerAsync()
    {
        await TenterAsync(async () =>
        {
            var (ouvrages, total) = await _corpus.BibliothequeAsync(Axe);
            Total = total;
            Ouvrages.Clear();
            foreach (var o in Filtrer(ouvrages))
                Ouvrages.Add(o);
        });
        OnPropertyChanged(nameof(Compteur));
    }

    private IEnumerable<Ouvrage> Filtrer(IEnumerable<Ouvrage> source)
    {
        if (string.IsNullOrWhiteSpace(Recherche)) return source;
        var terme = Recherche.Trim();
        return source.Where(o =>
            o.Titre.Contains(terme, StringComparison.OrdinalIgnoreCase)
            || o.Auteurs.Any(a => a.Contains(terme, StringComparison.OrdinalIgnoreCase)));
    }

    [RelayCommand]
    private Task OuvrirAsync(Ouvrage ouvrage) =>
        _navigateur.AllerAsync("ouvrage", new Dictionary<string, object> { ["id"] = ouvrage.Id });
}
