using Ascenda.Mobile.Pages;

namespace Ascenda.Mobile;

public partial class AppShell : Shell
{
    public AppShell()
    {
        InitializeComponent();
        Routing.RegisterRoute("connexion", typeof(ConnexionPage));
        Routing.RegisterRoute("quiz", typeof(QuizPage));
        Routing.RegisterRoute("correction", typeof(CorrectionPage));
    }
}
