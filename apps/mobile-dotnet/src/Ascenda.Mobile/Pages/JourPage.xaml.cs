using Ascenda.Noyau.VuesModeles;

namespace Ascenda.Mobile.Pages;

public partial class JourPage : ContentPage
{
    private readonly VmJour _vm;

    public JourPage(VmJour vm)
    {
        InitializeComponent();
        _vm = vm;
        BindingContext = vm;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await _vm.ChargerAsync();
    }
}
