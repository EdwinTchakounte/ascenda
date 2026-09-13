import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/modeles.dart';

final clientApiProvider = Provider<ClientApi>((ref) => ClientApi());

enum EtatSession { inconnu, deconnecte, connecte }

class Session {
  const Session({required this.etat, this.utilisateur});
  final EtatSession etat;
  final Utilisateur? utilisateur;

  bool get connecte => etat == EtatSession.connecte && utilisateur != null;
  bool get premium => utilisateur?.estPremium ?? false;
}

/// La session : un jeton en mémoire, un utilisateur, et rien d'autre.
///
/// Au démarrage on tente de reprendre la session enregistrée. Si le jeton n'est
/// plus valable, on retombe proprement sur l'état déconnecté au lieu de laisser
/// l'application dans un entre-deux.
class SessionNotifier extends StateNotifier<Session> {
  SessionNotifier(this._api) : super(const Session(etat: EtatSession.inconnu)) {
    reprendre();
  }

  final ClientApi _api;

  Future<void> reprendre() async {
    if (!await _api.aUneSession) {
      state = const Session(etat: EtatSession.deconnecte);
      return;
    }
    try {
      final j = await _api.get('/auth/moi') as Map<String, dynamic>;
      state = Session(etat: EtatSession.connecte, utilisateur: Utilisateur.depuisJson(j));
    } catch (e) {
      debugPrint('Session non reprise : $e');
      await _api.oublierJetons();
      state = const Session(etat: EtatSession.deconnecte);
    }
  }

  Future<void> connexion(String email, String motDePasse) async {
    final j = await _api.post('/auth/connexion',
        auth: false,
        corps: {'email': email.trim(), 'mot_de_passe': motDePasse}) as Map<String, dynamic>;
    await _ouvrir(j);
  }

  /// Ouvre le compte. Renvoie le message à montrer quand un code a été saisi :
  /// ce qu'il a ouvert, ou pourquoi il n'a pas pu l'être.
  Future<String?> inscription(String email, String motDePasse, String? nom,
      {String? code}) async {
    final j = await _api.post('/auth/inscription', auth: false, corps: {
      'email': email.trim(),
      'mot_de_passe': motDePasse,
      if (nom != null && nom.trim().isNotEmpty) 'nom': nom.trim(),
      if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
    }) as Map<String, dynamic>;
    await _ouvrir(j);
    final applique = j['code_applique'] as Map<String, dynamic>?;
    return applique?['message'] as String?;
  }

  Future<void> _ouvrir(Map<String, dynamic> j) async {
    final jetons = j['jetons'] as Map<String, dynamic>;
    await _api.enregistrerJetons('${jetons['access_token']}', '${jetons['refresh_token']}');
    state = Session(
      etat: EtatSession.connecte,
      utilisateur: Utilisateur.depuisJson(j['utilisateur'] as Map<String, dynamic>),
    );
  }

  Future<void> deconnexion() async {
    await _api.revoquerSession();
    await _api.oublierJetons();
    state = const Session(etat: EtatSession.deconnecte);
  }

  /// À appeler après un changement de formule pour rafraîchir le plan porté
  /// par la session sans forcer une reconnexion.
  Future<void> rafraichirUtilisateur() async {
    try {
      final j = await _api.get('/auth/moi') as Map<String, dynamic>;
      state = Session(etat: EtatSession.connecte, utilisateur: Utilisateur.depuisJson(j));
    } catch (_) {
      // Un échec ici ne doit pas déconnecter : l'état précédent reste valable.
    }
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, Session>(
  (ref) => SessionNotifier(ref.watch(clientApiProvider)),
);
