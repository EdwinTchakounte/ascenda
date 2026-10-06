using Ascenda.Noyau.VuesModeles;

namespace Ascenda.Mobile.Pages;

public partial class ProgressionPage : ContentPage
{
    private readonly VmJour _vm;

    public ProgressionPage(VmJour vm)
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
