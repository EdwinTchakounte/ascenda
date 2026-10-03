using System.Net;
using Ascenda.Noyau.Api;
using Ascenda.Noyau.Services;
using Xunit;

namespace Ascenda.Noyau.Tests;

public class ServicesTests
{
    private static (ServiceSession Session, FauxTransport Transport, StockageMemoire Stockage) Monter()
    {
        var transport = new FauxTransport();
        var http = new HttpClient(transport) { BaseAddress = new Uri("https://exemple.test") };
        var stockage = new StockageMemoire();
        return (new ServiceSession(new ClientApi(http, stockage)), transport, stockage);
    }

    [Fact]
    public async Task La_connexion_garde_les_jetons_et_publie_la_session()
    {
        var (service, transport, stockage) = Monter();
        transport.Repond(HttpStatusCode.OK,
            @"{""jetons"":{""access_token"":""a1"",""refresh_token"":""r1""},
               ""utilisateur"":{""id"":""u1"",""email"":""awa@exemple.test"",""nom"":""Awa Ndiaye"",
                                ""plan"":""premium"",""acces"":{""complet"":true,""fonctions"":[],
                                ""source"":""abonnement""}}}");
        var vues = new List<bool>();
        service.Changee += (_, s) => vues.Add(s.Connecte);

        var session = await service.ConnexionAsync("awa@exemple.test", "motdepasse");

        Assert.True(session.Connecte);
        Assert.Equal("Awa", session.Utilisateur!.Prenom);
        Assert.Equal("a1", await stockage.LireAsync(ClientApi.CleJeton));
        Assert.Equal(new[] { true }, vues);
    }

    [Fact]
    public async Task La_deconnexion_efface_tout()
    {
        var (service, transport, stockage) = Monter();
        transport.Repond(HttpStatusCode.OK,
            @"{""jetons"":{""access_token"":""a1"",""refresh_token"":""r1""},
               ""utilisateur"":{""id"":""u1"",""email"":""a@b.c"",""plan"":""free"",
                                ""acces"":{""complet"":false,""fonctions"":[],""source"":""aucun""}}}");
        await service.ConnexionAsync("a@b.c", "x");

        await service.DeconnexionAsync();

        Assert.False(service.Courante.Connecte);
        Assert.Null(await stockage.LireAsync(ClientApi.CleJeton));
    }

    [Fact]
    public async Task Sans_jeton_la_reprise_rend_une_session_vide_sans_appeler_le_service()
    {
        var (service, transport, _) = Monter();

        var session = await service.ReprendreAsync();

        Assert.False(session.Connecte);
        Assert.Empty(transport.Demandes);
    }

    [Fact]
    public async Task Le_quiz_envoie_ses_reponses_indexees_par_question()
    {
        var transport = new FauxTransport();
        var http = new HttpClient(transport) { BaseAddress = new Uri("https://exemple.test") };
        var service = new ServiceQuiz(new ClientApi(http, new StockageMemoire()));
        transport.Repond(HttpStatusCode.OK,
            @"{""score"":0.5,""justes"":1,""total"":2,
               ""details"":[{""index"":0,""juste"":true,""bonne_reponse"":1,""votre_reponse"":1},
                            {""index"":1,""juste"":false,""bonne_reponse"":0,""votre_reponse"":3}]}");

        var correction = await service.CorrigerAsync("q1",
            new Dictionary<int, int> { [0] = 1, [1] = 3 }, "s1", 240);

        Assert.NotNull(correction);
        Assert.Equal(1, correction!.Justes);
        Assert.Contains("\"0\":1", transport.Corps[0]);
        Assert.Contains("s1", transport.Corps[0]);
    }
}
