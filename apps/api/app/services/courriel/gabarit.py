"""L'habillage commun des courriels."""

_ENVELOPPE = """\
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{objet}</title>
</head>
<body style="margin:0;padding:0;background:#f2eee6;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f2eee6;">
<tr><td align="center" style="padding:32px 16px;">

<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
       style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;
              font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">

  <tr><td style="background:#0b1435;padding:26px 32px;">
    <div style="font-size:19px;font-weight:700;letter-spacing:3px;color:#e8c070;">ASCENDA</div>
    <div style="font-size:11px;letter-spacing:1.4px;color:#8590aa;margin-top:5px;
                text-transform:uppercase;">{oeil}</div>
  </td></tr>

  <tr><td style="padding:32px;color:#1a1f2e;font-size:15px;line-height:1.7;">
    <h1 style="margin:0 0 18px;font-size:20px;line-height:1.3;color:#0b1435;font-weight:600;">{objet}</h1>
    {corps}
  </td></tr>

  <tr><td style="padding:22px 32px;background:#faf8f4;border-top:1px solid rgba(11,20,53,0.08);
                 color:#6b7280;font-size:12px;line-height:1.65;">
    Ce message vous est envoyé parce que vous avez un compte ASCENDA.
    Nous ne vous demanderons jamais votre mot de passe ni votre code mobile money.
  </td></tr>

</table>

</td></tr>
</table>
</body>
</html>
"""

# Le surtitre de l'en-tête, déduit du code
_OEIL = {
    "bienvenue": "Votre compte",
    "paiement_confirme": "Paiement",
    "paiement_rejete": "Paiement",
    "abonnement_bientot_echu": "Votre abonnement",
    "abonnement_echu": "Votre abonnement",
}


def envelopper(code: str, objet: str, corps_html: str) -> str:
    return _ENVELOPPE.format(
        objet=objet,
        oeil=_OEIL.get(code, "ASCENDA"),
        corps=corps_html,
    )


def rendre(gabarit: str, contexte: dict) -> str:
    """Remplace les {jetons}. Un jeton manquant ne doit pas empêcher l'envoi."""
    try:
        return gabarit.format(**contexte)
    except (KeyError, IndexError, ValueError):
        return gabarit
