using System.Net;
using System.Text;

namespace Ascenda.Noyau.Tests;

/// Un transport qui répond ce qu'on lui a dit, et retient ce qu'on lui a demandé.
public sealed class FauxTransport : HttpMessageHandler
{
    private readonly Queue<(HttpStatusCode Code, string Corps)> _reponses = new();

    public List<HttpRequestMessage> Demandes { get; } = new();
    public List<string> Corps { get; } = new();

    public FauxTransport Repond(HttpStatusCode code, string corps)
    {
        _reponses.Enqueue((code, corps));
        return this;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Demandes.Add(request);
        Corps.Add(request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken));
        var (code, corps) = _reponses.Count > 0 ? _reponses.Dequeue() : (HttpStatusCode.OK, "null");
        return new HttpResponseMessage(code)
        {
            Content = new StringContent(corps, Encoding.UTF8, "application/json"),
        };
    }
}
