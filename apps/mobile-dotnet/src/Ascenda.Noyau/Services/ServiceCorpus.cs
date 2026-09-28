using Ascenda.Noyau.Api;
using Ascenda.Noyau.Modeles;

namespace Ascenda.Noyau.Services;

public class ServiceCorpus
{
    private readonly ClientApi _api;

    public ServiceCorpus(ClientApi api) => _api = api;

    public async Task<(IReadOnlyList<Ouvrage> Ouvrages, int Total)> BibliothequeAsync(
        string? axe = null, int page = 1)
    {
        var chemin = $"/v1/bibliotheque?page={page}" + (axe is null ? "" : $"&axe={axe}");
        var dto = await _api.LireAsync<BibliothequeDto>(chemin, auth: false);
        return (dto?.Ouvrages.Select(o => o.Vers()).ToList() ?? new List<Ouvrage>(),
                dto?.Total ?? 0);
    }

    public async Task<Ouvrage?> OuvrageAsync(string id) =>
        (await _api.LireAsync<OuvrageDto>($"/v1/bibliotheque/{id}", auth: false))?.Vers();

    public async Task<IReadOnlyList<Chapitre>> SommaireAsync(string documentId)
    {
        var dto = await _api.LireAsync<List<ChapitreDto>>(
            $"/v1/bibliotheque/{documentId}/sommaire", auth: false);
        return dto?.Select(c => c.Vers()).ToList() ?? new List<Chapitre>();
    }

    public async Task<Chapitre?> ChapitreAsync(string documentId, string chapitreId) =>
        (await _api.LireAsync<ChapitreDto>(
            $"/v1/lecteur/{documentId}/chapitre/{chapitreId}"))?.Vers();
}
