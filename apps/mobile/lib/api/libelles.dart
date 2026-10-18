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

String libelleQuota(String code) => libellesQuota[code] ?? code.replaceAll('_', ' ');

String periodeQuota(String code) => switch (code) {
      'day' => 'par jour',
      'month' => 'par mois',
      _ => 'au total',
    };

String valeurQuota(int? limite) {
  if (limite == null) return 'sans limite';
  if (limite == 0) return 'non';
  if (limite >= 1000) return 'sans limite';
  return '$limite';
}
