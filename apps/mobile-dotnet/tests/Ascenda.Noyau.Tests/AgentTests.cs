using System.Net;
using Ascenda.Noyau.Api;
using Ascenda.Noyau.Modeles;
using Ascenda.Noyau.Services;
using Ascenda.Noyau.VuesModeles;
using Xunit;

namespace Ascenda.Noyau.Tests;

public class AgentTests
{
    private static (VmAgent Vm, FauxTransport Transport) Monter()
    {
        var transport = new FauxTransport();
        var http = new HttpClient(transport) { BaseAddress = new Uri("https://exemple.test") };
        return (new VmAgent(new ServiceAgent(new ClientApi(http, new StockageMemoire()))), transport);
    }

    [Fact]
    public async Task Une_question_trop_courte_ne_part_pas()
    {
        var (vm, transport) = Monter();
        vm.Question = "ok";

        await vm.DemanderCommand.ExecuteAsync(null);

        Assert.Empty(transport.Demandes);
        Assert.Empty(vm.Echanges);
    }

    [Fact]
    public async Task La_reponse_arrive_avec_ses_sources()
    {
        var (vm, transport) = Monter();
        transport.Repond(HttpStatusCode.OK,
            @"{""reponse"":""L'érosion commence par l'impact des gouttes."",""degrade"":false,
               ""sources"":[{""ouvrage"":""Mémento de l'agronome"",""page"":245,
                             ""extrait"":""Sur un sol nu…""}]}");
        vm.Question = "Qu'est-ce qui déclenche l'érosion ?";

        await vm.DemanderCommand.ExecuteAsync(null);

        Assert.Equal(2, vm.Echanges.Count);
        Assert.True(vm.Echanges[0].DeMoi);
        Assert.Contains("gouttes", vm.Echanges[1].Texte);
        Assert.Equal("Mémento de l'agronome, p. 245", vm.Echanges[1].Resume);
        Assert.Equal("", vm.Question);
    }

    [Fact]
    public async Task Sans_redaction_automatique_l_agent_rend_les_passages()
    {
        var (vm, transport) = Monter();
        transport.Repond(HttpStatusCode.OK,
            @"{""reponse"":"""",""degrade"":true,
               ""sources"":[{""ouvrage"":""Panorama de l'IA"",""page"":12,""extrait"":""…""}]}");
        vm.Question = "Explique-moi les réseaux de neurones";

        await vm.DemanderCommand.ExecuteAsync(null);

        Assert.Contains("passages trouvés", vm.Echanges[1].Texte);
        Assert.True(vm.Echanges[1].ASources);
    }

    [Fact]
    public async Task Une_coupure_laisse_une_trace_dans_le_fil()
    {
        var http = new HttpClient(new TransportCoupe()) { BaseAddress = new Uri("https://exemple.test") };
        var vm = new VmAgent(new ServiceAgent(new ClientApi(http, new StockageMemoire())))
        {
            Question = "Une question posée hors réseau",
        };

        await vm.DemanderCommand.ExecuteAsync(null);

        Assert.Equal(2, vm.Echanges.Count);
        Assert.Contains("Pas de connexion", vm.Echanges[1].Texte);
        Assert.True(vm.Echanges[1].Degrade);
    }

    [Fact]
    public void La_pastille_du_jour_prend_la_teinte_de_son_etat()
    {
        var lundi = new DateOnly(2026, 10, 12);
        Assert.Equal("L", new JourSemaine(lundi, EtatSeance.AVenir, 1).Initiale);
        Assert.Equal("#D4A23F", new JourSemaine(lundi, EtatSeance.Faite, 1).Teinte);
        Assert.Equal("12", new JourSemaine(lundi, EtatSeance.Faite, 1).Quantieme);
    }

    private sealed class TransportCoupe : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,
                                                               CancellationToken cancellationToken)
            => throw new HttpRequestException("réseau absent");
    }
}
