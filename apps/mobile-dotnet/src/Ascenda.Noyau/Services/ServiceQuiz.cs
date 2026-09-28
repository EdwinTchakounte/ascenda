using Ascenda.Noyau.Api;
using Ascenda.Noyau.Modeles;

namespace Ascenda.Noyau.Services;

public class ServiceQuiz
{
    private readonly ClientApi _api;

    public ServiceQuiz(ClientApi api) => _api = api;

    public async Task<Quiz?> LireAsync(string quizId) =>
        (await _api.LireAsync<QuizDto>($"/v1/quiz/{quizId}"))?.Vers();

    public async Task<Correction?> CorrigerAsync(string quizId, IDictionary<int, int> reponses,
                                                 string? seanceId = null, int? dureeSec = null)
    {
        var corps = new
        {
            reponses = reponses.ToDictionary(p => p.Key.ToString(), p => p.Value),
            session_id = seanceId,
            duree_sec = dureeSec,
        };
        return (await _api.PosterAsync<CorrectionDto>($"/v1/quiz/{quizId}/corriger", corps))?.Vers();
    }
}
