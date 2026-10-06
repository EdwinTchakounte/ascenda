using Ascenda.Noyau.VuesModeles;

namespace Ascenda.Mobile.Pages;

public partial class BibliothequePage : ContentPage
{
    private readonly VmBibliotheque _vm;

    public BibliothequePage(VmBibliotheque vm)
    {
        InitializeComponent();
        _vm = vm;
        BindingContext = vm;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        if (_vm.Ouvrages.Count == 0)
            await _vm.ChargerAsync();
    }
}
