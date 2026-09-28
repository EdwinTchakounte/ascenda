using Ascenda.Noyau.Api;
using Ascenda.Noyau.Modeles;

namespace Ascenda.Noyau.Services;

public class ServiceSession
{
    private readonly ClientApi _api;

    public ServiceSession(ClientApi api) => _api = api;

    public Session Courante { get; private set; } = Session.Vide;

    public event EventHandler<Session>? Changee;

    public async Task<Session> ReprendreAsync()
    {
        if (!await _api.ASessionAsync()) return Poser(Session.Vide);
        try
        {
            var dto = await _api.LireAsync<UtilisateurDto>("/v1/auth/moi");
            return Poser(new Session(dto.Vers(), Courante.Jetons));
        }
        catch (ErreurApi e) when (e.Authentification)
        {
            await _api.OublierAsync();
            return Poser(Session.Vide);
        }
        catch (HorsLigne)
        {
            return Courante;
        }
    }

    public Task<Session> ConnexionAsync(string email, string motDePasse) =>
        OuvrirAsync("/v1/auth/connexion", new { email, mot_de_passe = motDePasse });

    public Task<Session> InscriptionAsync(string email, string motDePasse, string? nom,
                                          string? code) =>
        OuvrirAsync("/v1/auth/inscription",
            new { email, mot_de_passe = motDePasse, nom, code });

    public async Task DeconnexionAsync()
    {
        await _api.OublierAsync();
        Poser(Session.Vide);
    }

    private async Task<Session> OuvrirAsync(string chemin, object corps)
    {
        var dto = await _api.PosterAsync<SessionDto>(chemin, corps, auth: false)
                  ?? throw new ErreurApi(500, Messages.Defaut(500));
        if (dto.Jetons is null)
            throw new ErreurApi(500, "La réponse du service ne porte pas de jeton.");
        await _api.GarderJetonsAsync(dto.Jetons.Acces, dto.Jetons.Rafraichissement);
        var session = new Session(dto.Utilisateur.Vers(),
                                  new Jetons(dto.Jetons.Acces, dto.Jetons.Rafraichissement));
        return Poser(session.Utilisateur is null ? await ReprendreAsync() : session);
    }

    private Session Poser(Session session)
    {
        Courante = session;
        Changee?.Invoke(this, session);
        return session;
    }
}
