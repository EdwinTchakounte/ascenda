import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'reseau.dart';

/// Erreur remontée par l'API, avec le message destiné à l'utilisateur.
class ErreurApi implements Exception {
  ErreurApi(this.message, {this.code = 'erreur', this.statut = 0, this.quota});

  final String message;
  final String code;
  final int statut;
  final Map<String, dynamic>? quota;

  bool get estQuota => statut == 402;
  bool get estPremium => statut == 403;
  bool get estAuth => statut == 401;

  @override
  String toString() => message;
}

/// Perte de réseau. Distinguée d'une erreur serveur : le message et l'écran
/// à afficher ne sont pas les mêmes, et beaucoup de nos lecteurs sont sur des
/// connexions intermittentes.
class HorsLigne implements Exception {
  const HorsLigne();
  @override
  String toString() => 'Pas de connexion.';
}

/// Client HTTP de l'API ASCENDA.
///
/// Il porte le jeton d'accès, le renouvelle tout seul quand il expire, et
/// rejoue la requête une fois. L'appelant n'a donc jamais à gérer le
/// rafraîchissement, sauf quand la session est réellement perdue.
class ClientApi {
  ClientApi({String? base})
      : base = base ??
            const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8250');

  final String base;
  final _http = Reseau.client();

  static const _cleAcces = 'ascenda_acces';
  static const _cleRefresh = 'ascenda_refresh';
  static const _cleProfil = 'ascenda_profil';

  String? _acces;
  String? _refresh;
  bool _charge = false;

  Future<void> _charger() async {
    if (_charge) return;
    final p = await SharedPreferences.getInstance();
    _acces = p.getString(_cleAcces);
    _refresh = p.getString(_cleRefresh);
    _charge = true;
  }

  Future<void> enregistrerJetons(String acces, String refresh) async {
    _acces = acces;
    _refresh = refresh;
    _charge = true;
    final p = await SharedPreferences.getInstance();
    await p.setString(_cleAcces, acces);
    await p.setString(_cleRefresh, refresh);
  }

  Future<void> oublierJetons() async {
    _acces = null;
    _refresh = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_cleAcces);
    await p.remove(_cleRefresh);
    await p.remove(_cleProfil);
  }

  /// Le dernier profil reçu du serveur. Il sert à rouvrir la session sans
  /// réseau : un lecteur qui a emporté un ouvrage doit pouvoir le lire en zone
  /// blanche, pas retomber sur l'écran d'accueil.
  Future<void> garderProfil(Map<String, dynamic> j) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_cleProfil, jsonEncode(j));
  }

  Future<Map<String, dynamic>?> profilGarde() async {
    final p = await SharedPreferences.getInstance();
    final brut = p.getString(_cleProfil);
    if (brut == null) return null;
    try {
      return jsonDecode(brut) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Révoque le jeton de rafraîchissement côté serveur.
  ///
  /// Effacer les jetons du téléphone ne fermait rien : le jeton restait valable
  /// soixante jours en base. Sur un appareil perdu ou revendu, quelqu'un qui
  /// retrouvait la valeur rouvrait le compte. On prévient donc le serveur.
  ///
  /// L'appel ne bloque pas la déconnexion : si le réseau manque, l'utilisateur
  /// a quand même demandé à sortir et on le fait sortir. Le jeton finira par
  /// expirer.
  Future<void> revoquerSession() async {
    await _charger();
    final jeton = _refresh;
    if (jeton == null) return;
    try {
      // La route est authentifiée : elle ne révoque que les jetons du porteur.
      // On passe donc par l'envoi normal, qui pose l'en-tête et renouvelle
      // l'accès si celui du téléphone vient d'expirer.
      await post('/auth/deconnexion', corps: {'refresh_token': jeton});
    } catch (e) {
      debugPrint('Révocation impossible, sortie locale quand même : $e');
    }
  }

  Future<bool> get aUneSession async {
    await _charger();
    return _refresh != null;
  }

  /// Qui appelle. Un ouvrage réservé à l'application ne se sert en entier qu'aux
  /// clients mobiles : la version web ne reçoit que des extraits.
  static String get client {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'bureau';
  }

  Uri _uri(String chemin, [Map<String, dynamic>? params]) {
    final q = params?.entries
        .where((e) => e.value != null)
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}')
        .join('&');
    return Uri.parse('$base/v1$chemin${(q != null && q.isNotEmpty) ? '?$q' : ''}');
  }

  Future<dynamic> _envoyer(
    String methode,
    String chemin, {
    Map<String, dynamic>? params,
    Object? corps,
    bool authentifie = true,
    bool rejoue = true,
  }) async {
    await _charger();
    final entetes = <String, String>{'Content-Type': 'application/json', 'X-Ascenda-Client': client};
    if (authentifie && _acces != null) entetes['Authorization'] = 'Bearer $_acces';

    http.Response r;
    try {
      final uri = _uri(chemin, params);
      final donnees = corps == null ? null : jsonEncode(corps);
      final envoi = switch (methode) {
        'GET' => _http.get(uri, headers: entetes),
        'POST' => _http.post(uri, headers: entetes, body: donnees),
        'PATCH' => _http.patch(uri, headers: entetes, body: donnees),
        'DELETE' => _http.delete(uri, headers: entetes, body: donnees),
        _ => throw ArgumentError('Méthode inconnue : $methode'),
      };
      r = await envoi.timeout(const Duration(seconds: 25));
    } on HandshakeException catch (e) {
      // Le réseau fonctionne, mais la connexion sécurisée n'a pas abouti. Dire
      // « pas de connexion » enverrait le lecteur vérifier un réseau qui va
      // bien. La cause la plus fréquente est une heure du téléphone fausse.
      debugPrint('Échec TLS vers $base : $e');
      throw ErreurApi(
        "La connexion sécurisée au serveur a échoué. Vérifiez que la date et "
        "l'heure du téléphone sont justes, puis réessayez.",
        code: 'tls',
      );
    } on SocketException catch (e) {
      debugPrint('Réseau injoignable ($base) : $e');
      throw const HorsLigne();
    } on http.ClientException catch (e) {
      debugPrint('Requête interrompue ($base) : $e');
      throw const HorsLigne();
    } catch (e) {
      if (e.toString().contains('TimeoutException')) throw const HorsLigne();
      rethrow;
    }

    // Jeton expiré : on le renouvelle une fois, puis on rejoue la requête.
    if (r.statusCode == 401 && authentifie && rejoue && _refresh != null) {
      if (await _renouveler()) {
        return _envoyer(methode, chemin,
            params: params, corps: corps, authentifie: authentifie, rejoue: false);
      }
    }

    if (r.statusCode == 204 || r.body.isEmpty) return null;

    dynamic json;
    try {
      json = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      json = null;
    }

    if (r.statusCode >= 400) {
      throw _erreur(r.statusCode, json);
    }
    return json;
  }

  ErreurApi _erreur(int statut, dynamic json) {
    if (json is Map && json['detail'] is Map) {
      final d = json['detail'] as Map;
      return ErreurApi(
        '${d['message'] ?? 'Une erreur est survenue.'}',
        code: '${d['code'] ?? 'erreur'}',
        statut: statut,
        quota: d['quota'] is Map ? Map<String, dynamic>.from(d['quota'] as Map) : null,
      );
    }
    if (json is Map && json['detail'] is List) {
      // Erreur de validation : on ne montre pas le détail technique à l'écran.
      return ErreurApi('Certaines informations saisies ne conviennent pas.',
          code: 'validation', statut: statut);
    }
    if (json is Map && json['message'] != null) {
      return ErreurApi('${json['message']}', code: '${json['code'] ?? 'erreur'}', statut: statut);
    }
    return ErreurApi(
      statut >= 500
          ? "Le service ne répond pas correctement. Réessayez dans un instant."
          : "Requête refusée.",
      statut: statut,
    );
  }

  Future<bool> _renouveler() async {
    try {
      final r = await _http
          .post(_uri('/auth/rafraichir'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'refresh_token': _refresh}))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        await oublierJetons();
        return false;
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      await enregistrerJetons('${j['access_token']}', '${j['refresh_token']}');
      return true;
    } catch (e) {
      debugPrint('Renouvellement impossible : $e');
      return false;
    }
  }

  /// Télécharge un fichier en flux, en signalant l'avancement.
  ///
  /// Pour les PDF : certains pèsent des dizaines de mégaoctets, et une barre
  /// qui avance vaut mieux qu'un écran qui semble figé sur une connexion lente.
  Future<Uint8List> telecharger(
    String chemin, {
    void Function(int recu, int? total)? progression,
  }) async {
    await _charger();
    final requete = http.Request('GET', _uri(chemin))..headers['X-Ascenda-Client'] = client;
    if (_acces != null) requete.headers['Authorization'] = 'Bearer $_acces';
    final http.StreamedResponse r;
    try {
      r = await _http.send(requete).timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const HorsLigne();
    } on http.ClientException {
      throw const HorsLigne();
    } catch (e) {
      if (e.toString().contains('TimeoutException')) throw const HorsLigne();
      rethrow;
    }
    if (r.statusCode >= 400) {
      final corps = await r.stream.bytesToString();
      dynamic json;
      try {
        json = jsonDecode(corps);
      } catch (_) {}
      throw _erreur(r.statusCode, json);
    }
    final morceaux = BytesBuilder(copy: false);
    var recu = 0;
    try {
      await for (final m in r.stream) {
        morceaux.add(m);
        recu += m.length;
        progression?.call(recu, r.contentLength);
      }
    } on http.ClientException {
      throw const HorsLigne();
    } on SocketException {
      throw const HorsLigne();
    }
    return morceaux.takeBytes();
  }

  Future<dynamic> get(String chemin, {Map<String, dynamic>? params, bool auth = true}) =>
      _envoyer('GET', chemin, params: params, authentifie: auth);

  Future<dynamic> post(String chemin, {Object? corps, bool auth = true}) =>
      _envoyer('POST', chemin, corps: corps, authentifie: auth);

  Future<dynamic> patch(String chemin, {Object? corps}) =>
      _envoyer('PATCH', chemin, corps: corps);

  Future<dynamic> delete(String chemin, {Object? corps}) =>
      _envoyer('DELETE', chemin, corps: corps);
}
