using Ascenda.Noyau.VuesModeles;

namespace Ascenda.Mobile.Pages;

public partial class CorrectionPage : ContentPage
{
    public CorrectionPage(VmQuiz vm)
    {
        InitializeComponent();
        BindingContext = vm;
    }
}
