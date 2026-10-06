using Ascenda.Noyau.Api;
using Ascenda.Noyau.Navigation;
using Ascenda.Noyau.Services;
using Ascenda.Noyau.VuesModeles;
using Ascenda.Mobile.Pages;
using Ascenda.Mobile.Plateforme;
using Microsoft.Extensions.Logging;

namespace Ascenda.Mobile;

public static class MauiProgram
{
    public const string AdresseApi = "https://api.ascenda-books.online";

    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder();
        builder
            .UseMauiApp<App>()
            .ConfigureFonts(fonts =>
            {
                fonts.AddFont("Inter-Regular.ttf", "Inter");
                fonts.AddFont("Inter-SemiBold.ttf", "InterGras");
                fonts.AddFont("Fraunces-SemiBold.ttf", "Fraunces");
            });

#if DEBUG
        builder.Logging.AddDebug();
#endif

        builder.Services.AddSingleton<IStockage, StockageSecurise>();
        builder.Services.AddSingleton<INavigateur, NavigateurShell>();
        builder.Services.AddSingleton(_ => new HttpClient
        {
            BaseAddress = new Uri(AdresseApi),
            Timeout = TimeSpan.FromSeconds(30),
        });
        builder.Services.AddSingleton<ClientApi>();
        builder.Services.AddSingleton<ServiceSession>();
        builder.Services.AddSingleton<ServiceCorpus>();
        builder.Services.AddSingleton<ServiceParcours>();
        builder.Services.AddSingleton<ServiceQuiz>();
        builder.Services.AddSingleton<ServiceAgent>();

        builder.Services.AddTransient<VmConnexion>();
        builder.Services.AddTransient<VmJour>();
        builder.Services.AddTransient<VmBibliotheque>();
        builder.Services.AddTransient<VmQuiz>();
        builder.Services.AddTransient<VmAgent>();

        builder.Services.AddTransient<BienvenuePage>();
        builder.Services.AddTransient<ConnexionPage>();
        builder.Services.AddTransient<JourPage>();
        builder.Services.AddTransient<BibliothequePage>();
        builder.Services.AddTransient<QuizPage>();
        builder.Services.AddTransient<CorrectionPage>();
        builder.Services.AddTransient<ProgressionPage>();
        builder.Services.AddTransient<AgentPage>();

        return builder.Build();
    }
}
