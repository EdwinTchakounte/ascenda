using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Ascenda.Noyau.Api;

public class ClientApi
{
    public const string CleJeton = "ascenda.jeton";
    public const string CleRafraichissement = "ascenda.rafraichissement";

    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly HttpClient _http;
    private readonly IStockage _stockage;
    private readonly SemaphoreSlim _verrou = new(1, 1);

    public ClientApi(HttpClient http, IStockage stockage)
    {
        _http = http;
        _stockage = stockage;
    }

    public virtual async Task<bool> ASessionAsync() =>
        !string.IsNullOrEmpty(await _stockage.LireAsync(CleJeton));

    public virtual Task<T?> LireAsync<T>(string chemin, bool auth = true) =>
        EnvoyerAsync<T>(HttpMethod.Get, chemin, null, auth);

    public virtual Task<T?> PosterAsync<T>(string chemin, object? corps = null, bool auth = true) =>
        EnvoyerAsync<T>(HttpMethod.Post, chemin, corps, auth);

    public virtual Task<T?> ModifierAsync<T>(string chemin, object? corps = null) =>
        EnvoyerAsync<T>(HttpMethod.Patch, chemin, corps, true);

    public async Task GarderJetonsAsync(string acces, string rafraichissement)
    {
        await _stockage.EcrireAsync(CleJeton, acces);
        await _stockage.EcrireAsync(CleRafraichissement, rafraichissement);
    }

    public async Task OublierAsync()
    {
        await _stockage.EffacerAsync(CleJeton);
        await _stockage.EffacerAsync(CleRafraichissement);
    }

    private async Task<T?> EnvoyerAsync<T>(HttpMethod methode, string chemin, object? corps,
                                           bool auth, bool rejoue = false)
    {
        using var requete = new HttpRequestMessage(methode, chemin);
        if (corps is not null)
            requete.Content = JsonContent.Create(corps, options: Options);
        if (auth)
        {
            var jeton = await _stockage.LireAsync(CleJeton);
            if (!string.IsNullOrEmpty(jeton))
                requete.Headers.Authorization = new("Bearer", jeton);
        }

        HttpResponseMessage reponse;
        try
        {
            reponse = await _http.SendAsync(requete);
        }
        catch (HttpRequestException)
        {
            throw new HorsLigne();
        }
        catch (TaskCanceledException)
        {
            throw new HorsLigne();
        }

        if (reponse.StatusCode == HttpStatusCode.Unauthorized && auth && !rejoue
            && await RafraichirAsync())
            return await EnvoyerAsync<T>(methode, chemin, corps, auth, true);

        if (!reponse.IsSuccessStatusCode)
            throw await ComposerErreurAsync(reponse);

        if (reponse.StatusCode == HttpStatusCode.NoContent)
            return default;

        var texte = await reponse.Content.ReadAsStringAsync();
        return string.IsNullOrWhiteSpace(texte)
            ? default
            : JsonSerializer.Deserialize<T>(texte, Options);
    }

    private static async Task<ErreurApi> ComposerErreurAsync(HttpResponseMessage reponse)
    {
        var brut = await reponse.Content.ReadAsStringAsync();
        var message = Messages.Defaut((int)reponse.StatusCode);
        try
        {
            using var doc = JsonDocument.Parse(brut);
            if (doc.RootElement.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String)
                message = m.GetString() ?? message;
            else if (doc.RootElement.TryGetProperty("detail", out var d) && d.ValueKind == JsonValueKind.String)
                message = d.GetString() ?? message;
        }
        catch (JsonException)
        {
        }
        return new ErreurApi((int)reponse.StatusCode, message, brut.Length > 400 ? null : brut);
    }

    private async Task<bool> RafraichirAsync()
    {
        await _verrou.WaitAsync();
        try
        {
            var refresh = await _stockage.LireAsync(CleRafraichissement);
            if (string.IsNullOrEmpty(refresh)) return false;

            using var requete = new HttpRequestMessage(HttpMethod.Post, "/v1/auth/rafraichir")
            {
                Content = JsonContent.Create(new { refresh_token = refresh }, options: Options),
            };
            var reponse = await _http.SendAsync(requete);
            if (!reponse.IsSuccessStatusCode)
            {
                await OublierAsync();
                return false;
            }

            using var doc = JsonDocument.Parse(await reponse.Content.ReadAsStringAsync());
            var racine = doc.RootElement.TryGetProperty("jetons", out var j) ? j : doc.RootElement;
            var acces = racine.GetProperty("access_token").GetString();
            var suivant = racine.TryGetProperty("refresh_token", out var r)
                ? r.GetString() ?? refresh : refresh;
            if (string.IsNullOrEmpty(acces)) return false;
            await GarderJetonsAsync(acces, suivant);
            return true;
        }
        catch (Exception)
        {
            return false;
        }
        finally
        {
            _verrou.Release();
        }
    }
}

public static class Messages
{
    public static string Defaut(int code) => code switch
    {
        400 => "La demande n'a pas été comprise.",
        401 => "Votre session a expiré. Reconnectez-vous.",
        403 => "Cette partie demande un accès que votre compte n'a pas.",
        404 => "Introuvable.",
        409 => "Cette action entre en conflit avec l'état actuel.",
        422 => "Une valeur envoyée n'est pas valide.",
        429 => "Trop de demandes. Patientez un instant.",
        503 => "Le service est en maintenance. Réessayez dans quelques minutes.",
        _ => "Une erreur inattendue est survenue.",
    };
}
