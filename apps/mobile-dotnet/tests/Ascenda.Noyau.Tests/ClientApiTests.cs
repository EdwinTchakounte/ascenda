using System.Net;
using Ascenda.Noyau.Api;
using Xunit;

namespace Ascenda.Noyau.Tests;

public class ClientApiTests
{
    private static (ClientApi Api, FauxTransport Transport, StockageMemoire Stockage) Monter()
    {
        var transport = new FauxTransport();
        var http = new HttpClient(transport) { BaseAddress = new Uri("https://exemple.test") };
        var stockage = new StockageMemoire();
        return (new ClientApi(http, stockage), transport, stockage);
    }

    [Fact]
    public async Task Le_jeton_part_dans_l_en_tete()
    {
        var (api, transport, stockage) = Monter();
        await stockage.EcrireAsync(ClientApi.CleJeton, "jeton-abc");
        transport.Repond(HttpStatusCode.OK, "{\"id\":\"u1\"}");

        await api.LireAsync<Dictionary<string, object>>("/v1/auth/moi");

        Assert.Equal("Bearer", transport.Demandes[0].Headers.Authorization?.Scheme);
        Assert.Equal("jeton-abc", transport.Demandes[0].Headers.Authorization?.Parameter);
    }

    [Fact]
    public async Task Un_401_declenche_un_rafraichissement_puis_rejoue()
    {
        var (api, transport, stockage) = Monter();
        await stockage.EcrireAsync(ClientApi.CleJeton, "perime");
        await stockage.EcrireAsync(ClientApi.CleRafraichissement, "refresh-1");
        transport.Repond(HttpStatusCode.Unauthorized, "{\"message\":\"expiré\"}")
                 .Repond(HttpStatusCode.OK, "{\"access_token\":\"neuf\",\"refresh_token\":\"refresh-2\"}")
                 .Repond(HttpStatusCode.OK, "{\"id\":\"u1\"}");

        var r = await api.LireAsync<Dictionary<string, object>>("/v1/auth/moi");

        Assert.NotNull(r);
        Assert.Equal(3, transport.Demandes.Count);
        Assert.Equal("neuf", await stockage.LireAsync(ClientApi.CleJeton));
        Assert.Equal("refresh-2", await stockage.LireAsync(ClientApi.CleRafraichissement));
    }

    [Fact]
    public async Task Un_rafraichissement_refuse_efface_la_session()
    {
        var (api, transport, stockage) = Monter();
        await stockage.EcrireAsync(ClientApi.CleJeton, "perime");
        await stockage.EcrireAsync(ClientApi.CleRafraichissement, "refresh-1");
        transport.Repond(HttpStatusCode.Unauthorized, "{}")
                 .Repond(HttpStatusCode.Unauthorized, "{}");

        await Assert.ThrowsAsync<ErreurApi>(() => api.LireAsync<object>("/v1/auth/moi"));
        Assert.Null(await stockage.LireAsync(ClientApi.CleJeton));
    }

    [Fact]
    public async Task Le_message_du_service_est_prefere_au_message_par_defaut()
    {
        var (api, transport, _) = Monter();
        transport.Repond(HttpStatusCode.Conflict, "{\"message\":\"Votre demande est déjà envoyée.\"}");

        var e = await Assert.ThrowsAsync<ErreurApi>(() => api.LireAsync<object>("/v1/cercle", auth: false));
        Assert.Equal(409, e.Code);
        Assert.Equal("Votre demande est déjà envoyée.", e.Message);
    }

    [Fact]
    public async Task Une_coupure_reseau_devient_une_erreur_lisible()
    {
        var http = new HttpClient(new TransportMuet()) { BaseAddress = new Uri("https://exemple.test") };
        var api = new ClientApi(http, new StockageMemoire());

        await Assert.ThrowsAsync<HorsLigne>(() => api.LireAsync<object>("/v1/aujourdhui", auth: false));
    }

    private sealed class TransportMuet : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,
                                                               CancellationToken cancellationToken)
            => throw new HttpRequestException("réseau absent");
    }
}
