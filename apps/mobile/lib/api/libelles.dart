/// Les libellés des compteurs d'usage, en un seul endroit.
///
/// Ils étaient écrits dans le profil, et l'écran d'abonnement en aurait eu
/// besoin d'une seconde copie. Le jour où l'API ajoute un compteur, il n'y a
/// qu'une liste à compléter.
library;

const Map<String, String> libellesQuota = {
  'agent_question': "Questions à l'agent",
  'doc_uploaded': 'Documents importés',
  'ocr_pages': 'Pages reconnues',
  'quiz_generated': 'Quiz générés',
  'synthesis_generated': 'Synthèses générées',
  'chronogram_active': 'Chronogrammes actifs',
  'export_pdf': 'Exports PDF',
};

/// Un compteur que l'API connaîtrait sans que nous l'ayons traduit s'affiche
/// tel quel plutôt que de disparaître : un quota invisible est un quota qu'on
/// découvre en le heurtant.
String libelleQuota(String code) => libellesQuota[code] ?? code.replaceAll('_', ' ');

String periodeQuota(String code) => switch (code) {
      'day' => 'par jour',
      'month' => 'par mois',
      _ => 'au total',
    };

/// Zéro veut dire « pas du tout », et un plafond très haut veut dire « sans
/// compter ». Écrire « 10000 par jour » ferait croire à une limite qu'on
/// pourrait atteindre.
String valeurQuota(int? limite) {
  if (limite == null) return 'sans limite';
  if (limite == 0) return 'non';
  if (limite >= 1000) return 'sans limite';
  return '$limite';
}
