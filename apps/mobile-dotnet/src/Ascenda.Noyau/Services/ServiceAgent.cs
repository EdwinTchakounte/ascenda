using Ascenda.Noyau.Api;
using Ascenda.Noyau.Modeles;

namespace Ascenda.Noyau.Services;

public class ServiceAgent
{
    private readonly ClientApi _api;

    public ServiceAgent(ClientApi api) => _api = api;

    public async Task<Echange> DemanderAsync(string question, string? documentId = null)
    {
        var dto = await _api.PosterAsync<ReponseAgentDto>("/v1/agent/questions",
            new { question, document_id = documentId });

        var sources = (dto?.Sources ?? new List<SourceDto>())
            .Select(s => new Source(s.Ouvrage ?? "", s.Chapitre, s.Page, s.Extrait ?? ""))
            .ToList();

        var texte = string.IsNullOrWhiteSpace(dto?.Reponse)
            ? "La rédaction automatique n'est pas activée. Voici les passages trouvés."
            : dto!.Reponse!;

        return new Echange("assistant", texte, sources, dto?.Degrade ?? false);
    }
}
