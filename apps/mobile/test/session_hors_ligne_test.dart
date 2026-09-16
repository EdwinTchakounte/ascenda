// Ce que ce fichier vérifie : sans réseau, l'application garde la session.
//
// Un lecteur qui a emporté un ouvrage l'ouvre souvent en zone blanche. Au
// démarrage, la vérification du compte échoue faute de réseau : effacer les
// jetons à ce moment le renvoyait sur l'écran d'accueil, ouvrage inaccessible.
// Seul un refus du serveur (401) ferme la session.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ascenda/api/client.dart';
import 'package:ascenda/etat/session.dart';

const _profil = {'id': 'u-1', 'email': 'lecteur@example.com', 'nom': 'Kouam', 'plan': 'premium'};

class _Client extends ClientApi {
  _Client(this.reponse);
  final Object reponse;

  @override
  Future<dynamic> get(String chemin, {Map<String, dynamic>? params, bool auth = true}) async {
    if (reponse is Exception) throw reponse;
    return reponse;
  }
}

Future<Session> _demarrer(ClientApi api) async {
  final n = SessionNotifier(api);
  for (var i = 0; i < 50 && n.state.etat == EtatSession.inconnu; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return n.state;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'ascenda_acces': 'a', 'ascenda_refresh': 'r'});
    await ClientApi().garderProfil(Map<String, dynamic>.from(_profil));
  });

  test('sans réseau : session gardée avec le dernier profil', () async {
    final s = await _demarrer(_Client(const HorsLigne()));
    expect(s.connecte, isTrue);
    expect(s.utilisateur!.nom, 'Kouam');
    expect(await _Client(const HorsLigne()).aUneSession, isTrue);
  });

  test('serveur en panne : session gardée', () async {
    final s = await _demarrer(_Client(ErreurApi('panne', statut: 503)));
    expect(s.connecte, isTrue);
  });

  test('refus du serveur : jetons et profil effacés', () async {
    final s = await _demarrer(_Client(ErreurApi('expirée', statut: 401)));
    expect(s.etat, EtatSession.deconnecte);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('ascenda_refresh'), isNull);
    expect(p.getString('ascenda_profil'), isNull);
  });

  test('sans réseau et sans profil gardé : écran d\'accueil, mais jetons conservés', () async {
    final p = await SharedPreferences.getInstance();
    await p.remove('ascenda_profil');
    final s = await _demarrer(_Client(const HorsLigne()));
    expect(s.etat, EtatSession.deconnecte);
    expect(p.getString('ascenda_refresh'), 'r');
  });

  test('en ligne : le profil reçu est gardé pour la prochaine fois', () async {
    final s = await _demarrer(_Client({..._profil, 'nom': 'Kouam T.'}));
    expect(s.utilisateur!.nom, 'Kouam T.');
    expect((await ClientApi().profilGarde())!['nom'], 'Kouam T.');
  });
}
