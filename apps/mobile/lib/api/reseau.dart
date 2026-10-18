import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Le transport HTTP de l'application, préparé une fois au démarrage.
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
