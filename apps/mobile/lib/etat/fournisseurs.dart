import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import 'hors_ligne.dart';
import 'session.dart';

final aujourdhuiProvider = FutureProvider.autoDispose<Aujourdhui>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/aujourdhui') as Map<String, dynamic>;
  return Aujourdhui.depuisJson(j);
});

final axesProvider = FutureProvider<List<Axe>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/axes', auth: false) as List;
  return j.map((e) => Axe.depuisJson(e as Map<String, dynamic>)).toList();
});

class FiltreBiblio {
  const FiltreBiblio({this.axe, this.niveau, this.recherche, this.page = 1});

  final String? axe;
  final String? niveau;
  final String? recherche;
  final int page;

  FiltreBiblio a(int autrePage) =>
      FiltreBiblio(axe: axe, niveau: niveau, recherche: recherche, page: autrePage);

  @override
  bool operator ==(Object other) =>
      other is FiltreBiblio &&
      other.axe == axe &&
      other.niveau == niveau &&
      other.recherche == recherche &&
      other.page == page;

  @override
  int get hashCode => Object.hash(axe, niveau, recherche, page);
}

class PageOuvrages {
  const PageOuvrages({required this.ouvrages, required this.total, required this.page});

  final List<Ouvrage> ouvrages;
  final int total;
  final int page;

  bool get encore => ouvrages.length < total;
}

const int parPageBiblio = 24;

final bibliothequeProvider =
    FutureProvider.autoDispose.family<PageOuvrages, FiltreBiblio>((ref, f) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/bibliotheque', auth: false, params: {
    'par_page': parPageBiblio,
    'page': f.page,
    if (f.axe != null) 'axe': f.axe,
    if (f.niveau != null) 'niveau': f.niveau,
    if (f.recherche != null && f.recherche!.length >= 2) 'q': f.recherche,
  }) as Map<String, dynamic>;
  return PageOuvrages(
    ouvrages: (j['ouvrages'] as List)
        .map((e) => Ouvrage.depuisJson(e as Map<String, dynamic>))
        .toList(),
    total: (j['total'] as int?) ?? 0,
    page: (j['page'] as int?) ?? 1,
  );
});

final ficheOuvrageProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final api = ref.watch(clientApiProvider);
  try {
    return await api.get('/bibliotheque/$id') as Map<String, dynamic>;
  } on HorsLigne {
    final depot = ref.read(depotHorsLigneProvider);
    final pack = await depot.lire(id);
    if (pack == null) rethrow;
    return ficheHorsLigne(pack, pdf: await depot.aPdf(id));
  }
});

final sommaireProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final api = ref.watch(clientApiProvider);
  try {
    final j = await api.get('/bibliotheque/$id/sommaire', auth: false) as List;
    return j.cast<Map<String, dynamic>>();
  } on HorsLigne {
    final pack = await ref.read(depotHorsLigneProvider).lire(id);
    if (pack == null) rethrow;
    return sommaireHorsLigne(pack);
  }
});

final chronogrammesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/chronogrammes') as List;
  return j.cast<Map<String, dynamic>>();
});

final chronogrammeProvider =
    FutureProvider.autoDispose.family<Chronogramme, String>((ref, id) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/chronogrammes/$id') as Map<String, dynamic>;
  return Chronogramme.depuisJson(j);
});

final progressionProvider = FutureProvider.autoDispose<Progression>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/progression') as Map<String, dynamic>;
  return Progression.depuisJson(j);
});

final regulariteProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/progression/regularite', params: {'jours': 84})
      as Map<String, dynamic>;
  return (j['points'] as List).cast<Map<String, dynamic>>();
});

final maitriseProvider = FutureProvider.autoDispose<List<Notion>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/progression/maitrise') as List;
  return j.map((e) => Notion.depuisJson(e as Map<String, dynamic>)).toList();
});

final aReviserProvider = FutureProvider.autoDispose<List<Notion>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/concepts/a-reviser') as Map<String, dynamic>;
  return (j['notions'] as List).map((e) => Notion.depuisJson(e as Map<String, dynamic>)).toList();
});

final conversationsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/agent/conversations') as List;
  return j.cast<Map<String, dynamic>>();
});

final usageProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/compte/usage') as Map<String, dynamic>;
});

final codesProvider = FutureProvider.autoDispose<CodesEtAvantages>((ref) async {
  final api = ref.watch(clientApiProvider);
  return CodesEtAvantages.depuisJson(await api.get('/codes/moi') as Map<String, dynamic>);
});

final compteProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/compte') as Map<String, dynamic>;
});

final lectureProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String documentId, String chapitreId})>((ref, cle) async {
  final api = ref.watch(clientApiProvider);
  try {
    return await api.get('/lecteur/${cle.documentId}/chapitre/${cle.chapitreId}')
        as Map<String, dynamic>;
  } on HorsLigne {
    final pack = await ref.read(depotHorsLigneProvider).lire(cle.documentId);
    if (pack?['lecture_expiree'] == true) {
      throw ErreurApi(
        "Le texte emporté a expiré. Reconnectez-vous une fois : ASCENDA vérifie "
        "votre abonnement et le rend lisible hors ligne pour trente jours de plus.",
        code: 'hors_ligne_expire',
      );
    }
    final hors = pack == null ? null : chapitreHorsLigne(pack, cle.chapitreId);
    if (hors == null) rethrow;
    return hors;
  }
});

final lecturePagesProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String documentId, int debut, int fin})>((ref, cle) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/lecteur/${cle.documentId}/pages',
      params: {'debut': cle.debut, 'fin': cle.fin}) as Map<String, dynamic>;
});

final citationsProvider =
    FutureProvider.autoDispose.family<List<Citation>, String>((ref, documentId) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/lecteur/$documentId/citations', auth: false) as Map<String, dynamic>;
  return (j['citations'] as List)
      .map((e) => Citation.depuisJson({...e as Map<String, dynamic>, 'ouvrage': ''}))
      .toList();
});

final notesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String?>((ref, docId) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/notes', params: {'document_id': ?docId}) as List;
  return j.cast<Map<String, dynamic>>();
});

final tarifsProvider = FutureProvider.autoDispose<Tarifs>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/paiements/tarifs') as Map<String, dynamic>;
  return Tarifs.depuisJson(j);
});

final abonnementProvider = FutureProvider.autoDispose<Abonnement>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/paiements/abonnement/etat') as Map<String, dynamic>;
  return Abonnement.depuisJson(j);
});

final paiementsProvider = FutureProvider.autoDispose<List<Paiement>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/paiements') as List;
  return j.map((e) => Paiement.depuisJson(e as Map<String, dynamic>)).toList();
});

final surlignagesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, docId) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/surlignages', params: {'document_id': docId}) as List;
  return j.cast<Map<String, dynamic>>();
});

final rechercheProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, requete) async {
  final q = requete.trim();
  if (q.length < 3) return const {'resultats': [], 'mode': null, 'total': 0};
  final api = ref.watch(clientApiProvider);
  return await api.get('/recherche', auth: false, params: {'q': q, 'limite': 25})
      as Map<String, dynamic>;
});

final suggestionsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, requete) async {
  final q = requete.trim();
  if (q.length < 2) return const [];
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/recherche/suggestions', auth: false, params: {'q': q})
      as Map<String, dynamic>;
  return ((j['ouvrages'] as List?) ?? []).cast<Map<String, dynamic>>();
});

final quizOuvrageProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, documentId) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/quiz/document/$documentId', auth: false) as Map<String, dynamic>;
});

final historiqueQuizProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, documentId) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/quiz/document/$documentId/historique') as List;
  return j.cast<Map<String, dynamic>>();
});

final formulesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/compte/formules', auth: false) as List;
  return j.cast<Map<String, dynamic>>();
});

final journalProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/progression/journal', params: {'limite': 60}) as List;
  return j.cast<Map<String, dynamic>>();
});

final glossaireProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, ({String? axe, String q})>(
        (ref, f) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/concepts', auth: false, params: {
    'limite': 120,
    if (f.axe != null) 'axe': f.axe,
    if (f.q.length >= 2) 'q': f.q,
  }) as List;
  return j.cast<Map<String, dynamic>>();
});

final notionProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/concepts/$id', auth: false) as Map<String, dynamic>;
});

final axeProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, slug) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/axes/$slug', auth: false) as Map<String, dynamic>;
});

final etatServiceProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final api = ref.watch(clientApiProvider);
  Future<Map<String, dynamic>?> lire() async {
    try {
      return await api.get('/etat', auth: false) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  yield await lire();
  while (true) {
    await Future<void>.delayed(const Duration(minutes: 2));
    yield await lire();
  }
});

void rafraichirProgression(WidgetRef ref) {
  ref.invalidate(aujourdhuiProvider);
  ref.invalidate(progressionProvider);
  ref.invalidate(aReviserProvider);
  ref.invalidate(chronogrammesProvider);
}
