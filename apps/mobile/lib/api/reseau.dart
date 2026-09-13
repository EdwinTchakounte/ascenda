import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Le transport HTTP de l'application, préparé une fois au démarrage.
///
/// Le certificat de l'API remonte à ISRG Root X2, et, par une contre-signature,
/// à ISRG Root X1. Les téléphones n'ont pas tous ces racines : X1 n'est connue
/// qu'à partir d'Android 7.1.1, X2 qu'à partir d'Android 14. Plutôt que de
/// dépendre du magasin de certificats de chaque appareil, l'application
/// embarque les deux racines et les ajoute à celles du système. Les racines du
/// système restent valables : on élargit la confiance, on ne la remplace pas.
///
/// Sur le web, c'est le navigateur qui décide : il n'y a rien à préparer.
class Reseau {
  Reseau._();

  static SecurityContext? _contexte;

  /// Charge les racines embarquées. À appeler avant le premier appel réseau.
  static Future<void> preparer() async {
    if (kIsWeb || _contexte != null) return;
    final contexte = SecurityContext(withTrustedRoots: true);
    // Une racine à la fois : si le système connaît déjà l'une, son ajout lève
    // une erreur, et un ajout groupé aurait aussi perdu l'autre.
    for (final racine in const ['isrg-root-x1.pem', 'isrg-root-x2.pem']) {
      try {
        final octets = await rootBundle.load('assets/certificats/$racine');
        contexte.setTrustedCertificatesBytes(octets.buffer.asUint8List());
      } catch (e) {
        debugPrint('Racine $racine non ajoutée (déjà connue du système ?) : $e');
      }
    }
    _contexte = contexte;
  }

  /// Un client HTTP qui fait confiance aux racines embarquées.
  static http.Client client() {
    if (kIsWeb) return http.Client();
    final natif = HttpClient(context: _contexte)
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30);
    return IOClient(natif);
  }
}
