using Ascenda.Noyau.Api;
using Ascenda.Noyau.Modeles;

namespace Ascenda.Noyau.Services;

public class ServiceParcours
{
    private readonly ClientApi _api;

    public ServiceParcours(ClientApi api) => _api = api;

    public async Task<Journee?> JourneeAsync() =>
        (await _api.LireAsync<JourneeDto>("/v1/aujourdhui"))?.Vers();

    public async Task<Chronogramme?> ChronogrammeAsync(string id) =>
        (await _api.LireAsync<ChronogrammeDto>($"/v1/chronogrammes/{id}"))?.Vers();

    public async Task<IReadOnlyList<Chronogramme>> ChronogrammesAsync()
    {
        var dto = await _api.LireAsync<List<ChronogrammeDto>>("/v1/chronogrammes");
        return dto?.Select(c => c.Vers()).ToList() ?? new List<Chronogramme>();
    }

    public Task MarquerAsync(string seanceId, string statut, int? dureeReelle = null) =>
        _api.ModifierAsync<object>($"/v1/seances/{seanceId}",
            new { statut, duree_reelle_min = dureeReelle });

    public Task<Chronogramme?> CreerAsync(string axe, int minutesSemaine, int dureeSeance) =>
        _api.PosterAsync<ChronogrammeDto>("/v1/chronogrammes",
            new { axe, minutes_semaine = minutesSemaine, duree_seance = dureeSeance })
            .ContinueWith(t => t.Result?.Vers());

    public async Task<Progression?> ProgressionAsync() =>
        (await _api.LireAsync<ProgressionDto>("/v1/progression"))?.Vers();
}
