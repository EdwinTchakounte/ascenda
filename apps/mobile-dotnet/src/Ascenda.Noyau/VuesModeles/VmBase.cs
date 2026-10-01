using CommunityToolkit.Mvvm.ComponentModel;
using Ascenda.Noyau.Api;

namespace Ascenda.Noyau.VuesModeles;

public abstract partial class VmBase : ObservableObject
{
    [ObservableProperty] private bool _occupe;
    [ObservableProperty] private string? _erreur;
    [ObservableProperty] private string _titre = "";

    public bool EnEchec => !string.IsNullOrEmpty(Erreur);

    protected async Task<bool> TenterAsync(Func<Task> action)
    {
        if (Occupe) return false;
        Occupe = true;
        Erreur = null;
        try
        {
            await action();
            return true;
        }
        catch (HorsLigne e)
        {
            Erreur = e.Message;
        }
        catch (ErreurApi e)
        {
            Erreur = e.Message;
        }
        finally
        {
            Occupe = false;
        }
        return false;
    }

    partial void OnErreurChanged(string? value) => OnPropertyChanged(nameof(EnEchec));
}
