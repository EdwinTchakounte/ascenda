using Ascenda.Noyau.VuesModeles;

namespace Ascenda.Mobile.Pages;

[QueryProperty(nameof(Inscription), "inscription")]
public partial class ConnexionPage : ContentPage
{
    private readonly VmConnexion _vm;

    public ConnexionPage(VmConnexion vm)
    {
        InitializeComponent();
        _vm = vm;
        BindingContext = vm;
    }

    public string? Inscription
    {
        set
        {
            if (!string.IsNullOrEmpty(value) && _vm.Inscription == false)
                _vm.BasculerCommand.Execute(null);
        }
    }
}
