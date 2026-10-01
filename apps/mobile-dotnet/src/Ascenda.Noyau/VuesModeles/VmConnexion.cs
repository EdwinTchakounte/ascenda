using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Ascenda.Noyau.Navigation;
using Ascenda.Noyau.Services;

namespace Ascenda.Noyau.VuesModeles;

public partial class VmConnexion : VmBase
{
    private readonly ServiceSession _session;
    private readonly INavigateur _navigateur;

    public VmConnexion(ServiceSession session, INavigateur navigateur)
    {
        _session = session;
        _navigateur = navigateur;
        Titre = "Content de vous revoir";
    }

    [ObservableProperty] private string _email = "";
    [ObservableProperty] private string _motDePasse = "";
    [ObservableProperty] private string _nom = "";
    [ObservableProperty] private string _code = "";
    [ObservableProperty] private bool _inscription;

    public bool Valide => Email.Contains('@') && Email.Contains('.')
                          && MotDePasse.Length >= (Inscription ? 8 : 1);

    public string Etiquette => Inscription ? "NOUVEAU LECTEUR" : "RETOUR AU RAYON";

    public string Chapeau => Inscription
        ? "Gratuit, sans carte bancaire. Vous choisirez votre axe juste après."
        : "Reprenez votre chronogramme là où vous l'aviez laissé.";

    public string LibelleAction => Inscription ? "Créer mon compte" : "Me connecter";

    public string LibelleBascule => Inscription
        ? "J'ai déjà un compte"
        : "Je n'ai pas encore de compte";

    [RelayCommand]
    private void Basculer()
    {
        Inscription = !Inscription;
        Titre = Inscription ? "Créer votre compte" : "Content de vous revoir";
        Erreur = null;
    }

    [RelayCommand]
    private async Task ValiderAsync()
    {
        if (!Valide)
        {
            Erreur = Email.Contains('@')
                ? "Le mot de passe doit faire au moins huit caractères."
                : "Cette adresse ne semble pas valide.";
            return;
        }

        var ok = await TenterAsync(async () =>
        {
            if (Inscription)
                await _session.InscriptionAsync(Email.Trim(), MotDePasse,
                    string.IsNullOrWhiteSpace(Nom) ? null : Nom.Trim(),
                    string.IsNullOrWhiteSpace(Code) ? null : Code.Trim());
            else
                await _session.ConnexionAsync(Email.Trim(), MotDePasse);
        });

        if (ok)
            await _navigateur.AllerAsync(Inscription ? "//diagnostic" : "//jour");
    }

    partial void OnEmailChanged(string value) => OnPropertyChanged(nameof(Valide));
    partial void OnMotDePasseChanged(string value) => OnPropertyChanged(nameof(Valide));
    partial void OnInscriptionChanged(bool value)
    {
        OnPropertyChanged(nameof(Valide));
        OnPropertyChanged(nameof(Etiquette));
        OnPropertyChanged(nameof(Chapeau));
        OnPropertyChanged(nameof(LibelleAction));
        OnPropertyChanged(nameof(LibelleBascule));
    }
}
