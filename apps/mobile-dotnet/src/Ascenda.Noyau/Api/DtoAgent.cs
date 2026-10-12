using System.Text.Json.Serialization;

namespace Ascenda.Noyau.Api;

public sealed class SourceDto
{
    [JsonPropertyName("ouvrage")] public string? Ouvrage { get; set; }
    [JsonPropertyName("chapitre")] public string? Chapitre { get; set; }
    [JsonPropertyName("page")] public int? Page { get; set; }
    [JsonPropertyName("extrait")] public string? Extrait { get; set; }
}

public sealed class ReponseAgentDto
{
    [JsonPropertyName("reponse")] public string? Reponse { get; set; }
    [JsonPropertyName("degrade")] public bool Degrade { get; set; }
    [JsonPropertyName("sources")] public List<SourceDto> Sources { get; set; } = new();
}
