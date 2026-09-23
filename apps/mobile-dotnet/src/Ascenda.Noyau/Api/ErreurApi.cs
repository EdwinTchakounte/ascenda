namespace Ascenda.Noyau.Api;

public class ErreurApi : Exception
{
    public ErreurApi(int code, string message, string? detail = null) : base(message)
    {
        Code = code;
        Detail = detail;
    }

    public int Code { get; }
    public string? Detail { get; }

    public bool Authentification => Code is 401 or 403;
}

public sealed class HorsLigne : ErreurApi
{
    public HorsLigne() : base(0, "Pas de connexion. Vérifiez votre réseau et réessayez.") { }
}
