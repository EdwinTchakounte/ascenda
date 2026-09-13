import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/cercle.dart';
import 'session.dart';

final cercleMoiProvider = FutureProvider.autoDispose<CercleMoi>((ref) async {
  final j = await ref.watch(clientApiProvider).get('/cercle/moi') as Map<String, dynamic>;
  return CercleMoi.depuisJson(j);
});

final amisProvider = FutureProvider.autoDispose<List<Ami>>((ref) async {
  final j = await ref.watch(clientApiProvider).get('/cercle/amis') as List;
  return [for (final a in j) Ami.depuisJson((a as Map).cast())];
});

final demandesProvider = FutureProvider.autoDispose<Demandes>((ref) async {
  final j = await ref.watch(clientApiProvider).get('/cercle/demandes') as Map<String, dynamic>;
  return Demandes.depuisJson(j);
});

final filProvider = FutureProvider.autoDispose<List<EvenementFil>>((ref) async {
  final j = await ref.watch(clientApiProvider).get('/cercle/fil') as List;
  return [for (final e in j) EvenementFil.depuisJson((e as Map).cast())];
});

final encouragementsProvider = FutureProvider.autoDispose<List<EncouragementRecu>>((ref) async {
  final j = await ref.watch(clientApiProvider).get('/cercle/encouragements') as List;
  return [for (final e in j) EncouragementRecu.depuisJson((e as Map).cast())];
});

final conversationProvider =
    FutureProvider.autoDispose.family<Conversation, String>((ref, amiId) async {
  final j = await ref.watch(clientApiProvider).get('/cercle/echanges/$amiId') as Map<String, dynamic>;
  return Conversation.depuisJson(j);
});

/// Tout ce que l'onglet affiche, rafraîchi d'un geste.
void rafraichirCercle(WidgetRef ref) {
  ref
    ..invalidate(cercleMoiProvider)
    ..invalidate(amisProvider)
    ..invalidate(demandesProvider)
    ..invalidate(filProvider)
    ..invalidate(encouragementsProvider);
}
