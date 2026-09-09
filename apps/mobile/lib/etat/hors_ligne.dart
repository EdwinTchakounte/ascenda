import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session.dart';

/// La bibliothèque hors ligne.
///
/// Un pack contient tout ce qu'ASCENDA sait d'un ouvrage : fiche, idées-force,
/// citations avec leurs pages, quiz jouables et corrigeables, plan de lecture.
/// Une fois rapatrié, il ne dépend plus du réseau.
///
/// Les packs pèsent de 50 Ko à 1 Mo : ils vont dans des fichiers, pas dans les
/// préférences, qui sont relues en entier à chaque accès. Sur le web, où le
/// système de fichiers n'existe pas, on retombe sur les préférences.

class PackHorsLigne {
  const PackHorsLigne({
    required this.documentId,
    required this.titre,
    required this.telechargeLe,
    required this.octets,
    required this.compteurs,
  });

  final String documentId;
  final String titre;
  final DateTime telechargeLe;
  final int octets;
  final Map<String, int> compteurs;

  String get poids => octets < 1024 * 1024
      ? '${(octets / 1024).round()} Ko'
      : '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';

  Map<String, dynamic> versJson() => {
        'document_id': documentId,
        'titre': titre,
        'telecharge_le': telechargeLe.toIso8601String(),
        'octets': octets,
        'compteurs': compteurs,
      };

  factory PackHorsLigne.depuisJson(Map<String, dynamic> j) => PackHorsLigne(
        documentId: '${j['document_id']}',
        titre: '${j['titre']}',
        telechargeLe: DateTime.parse('${j['telecharge_le']}'),
        octets: (j['octets'] as num?)?.toInt() ?? 0,
        compteurs: Map<String, int>.from(
          (j['compteurs'] as Map?)?.map((k, v) => MapEntry('$k', (v as num).toInt())) ?? {},
        ),
      );
}

class DepotHorsLigne {
  static const _cleIndex = 'ascenda_packs';

  Future<Directory?> _dossier() async {
    if (kIsWeb) return null;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/packs');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Map<String, PackHorsLigne>> index() async {
    final p = await SharedPreferences.getInstance();
    final brut = p.getString(_cleIndex);
    if (brut == null) return {};
    try {
      final m = jsonDecode(brut) as Map<String, dynamic>;
      return m.map((k, v) =>
          MapEntry(k, PackHorsLigne.depuisJson(v as Map<String, dynamic>)));
    } catch (_) {
      // Un index illisible ne doit pas bloquer l'application : on repart de zéro.
      return {};
    }
  }

  Future<void> _ecrireIndex(Map<String, PackHorsLigne> index) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _cleIndex,
      jsonEncode(index.map((k, v) => MapEntry(k, v.versJson()))),
    );
  }

  Future<void> enregistrer(String documentId, Map<String, dynamic> pack) async {
    final contenu = jsonEncode(pack);
    final octets = utf8.encode(contenu).length;

    final d = await _dossier();
    if (d != null) {
      await File('${d.path}/$documentId.json').writeAsString(contenu);
    } else {
      final p = await SharedPreferences.getInstance();
      await p.setString('ascenda_pack_$documentId', contenu);
    }

    final compteurs = Map<String, int>.from(
      (pack['compteurs'] as Map?)?.map((k, v) => MapEntry('$k', (v as num).toInt())) ?? {},
    );
    final actuel = await index();
    actuel[documentId] = PackHorsLigne(
      documentId: documentId,
      titre: '${(pack['ouvrage'] as Map)['titre']}',
      telechargeLe: DateTime.now(),
      octets: octets,
      compteurs: compteurs,
    );
    await _ecrireIndex(actuel);
  }

  Future<Map<String, dynamic>?> lire(String documentId) async {
    final d = await _dossier();
    try {
      if (d != null) {
        final f = File('${d.path}/$documentId.json');
        if (!await f.exists()) return null;
        return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      }
      final p = await SharedPreferences.getInstance();
      final brut = p.getString('ascenda_pack_$documentId');
      return brut == null ? null : jsonDecode(brut) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Pack illisible pour $documentId : $e');
      return null;
    }
  }

  Future<void> supprimer(String documentId) async {
    final d = await _dossier();
    if (d != null) {
      final f = File('${d.path}/$documentId.json');
      if (await f.exists()) await f.delete();
    } else {
      final p = await SharedPreferences.getInstance();
      await p.remove('ascenda_pack_$documentId');
    }
    final actuel = await index();
    actuel.remove(documentId);
    await _ecrireIndex(actuel);
  }

  Future<int> poidsTotal() async {
    final actuel = await index();
    return actuel.values.fold<int>(0, (s, p) => s + p.octets);
  }
}

final depotHorsLigneProvider = Provider((ref) => DepotHorsLigne());

/// L'index des packs présents sur l'appareil.
final packsProvider = FutureProvider<Map<String, PackHorsLigne>>((ref) async {
  return ref.watch(depotHorsLigneProvider).index();
});

/// Télécharge le pack d'un ouvrage et le range sur l'appareil.
final telechargerPackProvider =
    FutureProvider.autoDispose.family<PackHorsLigne, String>((ref, documentId) async {
  final api = ref.read(clientApiProvider);
  final depot = ref.read(depotHorsLigneProvider);
  final pack = await api.get('/bibliotheque/$documentId/pack', auth: false)
      as Map<String, dynamic>;
  await depot.enregistrer(documentId, pack);
  ref.invalidate(packsProvider);
  return (await depot.index())[documentId]!;
});

/// Le pack local d'un ouvrage, s'il a été téléchargé.
final packLocalProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, documentId) async {
  return ref.watch(depotHorsLigneProvider).lire(documentId);
});
