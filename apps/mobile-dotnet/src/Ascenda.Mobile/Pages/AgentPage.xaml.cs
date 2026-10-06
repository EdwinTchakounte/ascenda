using Ascenda.Noyau.VuesModeles;

namespace Ascenda.Mobile.Pages;

public partial class AgentPage : ContentPage
{
    public AgentPage(VmAgent vm)
    {
        InitializeComponent();
        BindingContext = vm;
    }
}
