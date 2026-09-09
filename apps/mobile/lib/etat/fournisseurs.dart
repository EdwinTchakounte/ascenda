import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/modeles.dart';
import 'session.dart';

/// Les lectures de données. Chaque famille est indexée par ce qui la
/// détermine, pour que Riverpod recharge exactement ce qui a changé.

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
  const FiltreBiblio({this.axe, this.niveau, this.recherche});
  final String? axe;
  final String? niveau;
  final String? recherche;

  @override
  bool operator ==(Object other) =>
      other is FiltreBiblio &&
      other.axe == axe &&
      other.niveau == niveau &&
      other.recherche == recherche;

  @override
  int get hashCode => Object.hash(axe, niveau, recherche);
}

final bibliothequeProvider =
    FutureProvider.autoDispose.family<List<Ouvrage>, FiltreBiblio>((ref, f) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/bibliotheque', auth: false, params: {
    'par_page': 60,
    if (f.axe != null) 'axe': f.axe,
    if (f.niveau != null) 'niveau': f.niveau,
    if (f.recherche != null && f.recherche!.length >= 2) 'q': f.recherche,
  }) as Map<String, dynamic>;
  return (j['ouvrages'] as List)
      .map((e) => Ouvrage.depuisJson(e as Map<String, dynamic>))
      .toList();
});

final ficheOuvrageProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/bibliotheque/$id', auth: false) as Map<String, dynamic>;
});

final sommaireProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/bibliotheque/$id/sommaire', auth: false) as List;
  return j.cast<Map<String, dynamic>>();
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

final compteProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/compte') as Map<String, dynamic>;
});

/// Le contenu d'un chapitre, sous contrôle de droits côté serveur.
final lectureProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String documentId, String chapitreId})>((ref, cle) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/lecteur/${cle.documentId}/chapitre/${cle.chapitreId}', auth: false)
      as Map<String, dynamic>;
});

/// Lecture par plage de pages : une séance qui regroupe plusieurs chapitres
/// couvre plus que le premier d'entre eux.
final lecturePagesProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String documentId, int debut, int fin})>((ref, cle) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/lecteur/${cle.documentId}/pages',
      auth: false, params: {'debut': cle.debut, 'fin': cle.fin}) as Map<String, dynamic>;
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

/// La grille tarifaire. Publique : un visiteur doit pouvoir voir les prix avant
/// d'ouvrir un compte. Elle ne dépend pas de la session, donc pas d'autoDispose :
/// la relire à chaque aller-retour vers l'écran d'abonnement n'apporte rien.
final tarifsProvider = FutureProvider<Tarifs>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/paiements/tarifs', auth: false) as Map<String, dynamic>;
  return Tarifs.depuisJson(j);
});

/// L'état de l'abonnement du membre, avec les jours restants avant fermeture.
final abonnementProvider = FutureProvider.autoDispose<Abonnement>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/paiements/abonnement/etat') as Map<String, dynamic>;
  return Abonnement.depuisJson(j);
});

/// L'historique des paiements. Un membre à qui l'on demande de l'argent a le
/// droit de voir ce qu'il a déjà versé, et quand.
final paiementsProvider = FutureProvider.autoDispose<List<Paiement>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/paiements') as List;
  return j.map((e) => Paiement.depuisJson(e as Map<String, dynamic>)).toList();
});

/// Les surlignages d'un ouvrage. Indexés par ouvrage et non globalement : le
/// lecteur n'a besoin que des siens, et un membre qui annote beaucoup en aurait
/// des centaines.
final surlignagesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, docId) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/surlignages', params: {'document_id': docId}) as List;
  return j.cast<Map<String, dynamic>>();
});

/// La recherche dans le corpus. Publique : elle est la vitrine du produit,
/// et un visiteur doit pouvoir voir ce que la bibliothèque contient avant
/// d'ouvrir un compte.
///
/// Le champ `mode` que renvoie l'API dit par quelle voie la réponse est venue :
/// plein texte, sémantique, ou les deux fusionnées. On l'affiche, parce qu'un
/// moteur qui explique comment il a trouvé se fait corriger plus vite.
final rechercheProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, requete) async {
  final q = requete.trim();
  if (q.length < 3) return const {'resultats': [], 'mode': null, 'total': 0};
  final api = ref.watch(clientApiProvider);
  return await api.get('/recherche', auth: false, params: {'q': q, 'limite': 25})
      as Map<String, dynamic>;
});

/// Les ouvrages dont le titre approche ce qu'on tape, pendant la frappe.
final suggestionsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, requete) async {
  final q = requete.trim();
  if (q.length < 2) return const [];
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/recherche/suggestions', auth: false, params: {'q': q})
      as Map<String, dynamic>;
  return ((j['ouvrages'] as List?) ?? []).cast<Map<String, dynamic>>();
});

/// Les quiz préparés pour un ouvrage, chapitre par chapitre.
///
/// Publique : un visiteur doit pouvoir voir ce que l'ouvrage contient comme
/// exercices avant d'ouvrir un compte. Passer le quiz, en revanche, demande
/// un compte, puisqu'il faut bien enregistrer le résultat quelque part.
final quizOuvrageProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, documentId) async {
  final api = ref.watch(clientApiProvider);
  return await api.get('/quiz/document/$documentId', auth: false) as Map<String, dynamic>;
});

/// Vos tentatives passées sur un ouvrage, la plus récente d'abord.
final historiqueQuizProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, documentId) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/quiz/document/$documentId/historique') as List;
  return j.cast<Map<String, dynamic>>();
});

/// La comparaison des formules, lue au serveur.
///
/// Les limites viennent de `plan_quota`, celle-là même que l'API applique, et
/// le prix de `plan_tarif`. Un descriptif recopié dans l'application finit
/// toujours par promettre autre chose que ce qui est réellement accordé.
final formulesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/compte/formules', auth: false) as List;
  return j.cast<Map<String, dynamic>>();
});

/// Le journal d'activité, le plus récent d'abord.
///
/// La table est en ajout seul : elle porte tout ce que le lecteur a fait, et
/// c'est d'elle que sortent les chiffres de la page Progression. La montrer
/// telle quelle permet de vérifier un total qu'on trouverait douteux.
final journalProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(clientApiProvider);
  final j = await api.get('/progression/journal', params: {'limite': 60}) as List;
  return j.cast<Map<String, dynamic>>();
});

/// Recharge tout ce qui dépend de la progression après une action.
/// Prend un WidgetRef : ces invalidations sont déclenchées depuis les écrans.
void rafraichirProgression(WidgetRef ref) {
  ref.invalidate(aujourdhuiProvider);
  ref.invalidate(progressionProvider);
  ref.invalidate(aReviserProvider);
  ref.invalidate(chronogrammesProvider);
}
