import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coffre.dart';
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
  DepotHorsLigne({Coffre? coffre, Future<Directory> Function()? racine})
      : _coffre = coffre ?? Coffre(),
        _racine = racine;

  static const _cleIndex = 'ascenda_packs';

  /// Le texte intégral d'un ouvrage réservé et son PDF sont chiffrés ; le reste
  /// du pack (fiche, quiz, citations) l'est aussi, dès lors qu'il voyage avec eux.
  final Coffre _coffre;
  final Future<Directory> Function()? _racine;

  Future<Directory?> _dossier() async {
    if (kIsWeb) return null;
    final base = await (_racine?.call() ?? getApplicationSupportDirectory());
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
    final integral = pack['lecture'] != null;

    final d = await _dossier();
    if (d != null) {
      // Toujours chiffré, et jamais sous un nom qui s'ouvrirait ailleurs.
      await File('${d.path}/$documentId.bin').writeAsBytes(await _coffre.chiffrerTexte(contenu), flush: true);
      final ancien = File('${d.path}/$documentId.json');
      if (await ancien.exists()) await ancien.delete();
    } else if (!integral) {
      // Le web n'a pas d'espace privé : il garde le compagnon de lecture, jamais
      // le texte d'un ouvrage réservé à l'application.
      final p = await SharedPreferences.getInstance();
      await p.setString('ascenda_pack_$documentId', contenu);
    } else {
      final p = await SharedPreferences.getInstance();
      await p.setString('ascenda_pack_$documentId', jsonEncode({...pack, 'lecture': null}));
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

  Future<Map<String, dynamic>?> lire(String documentId, {DateTime? maintenant}) async {
    final d = await _dossier();
    try {
      if (d != null) {
        final chiffre = File('${d.path}/$documentId.bin');
        Map<String, dynamic>? pack;
        if (await chiffre.exists()) {
          pack = jsonDecode(await _coffre.dechiffrerTexte(await chiffre.readAsBytes())) as Map<String, dynamic>;
        } else {
          // Un pack d'une version précédente, écrit en clair dans les documents :
          // lu une dernière fois, puis réécrit chiffré au prochain téléchargement.
          final documents = await getApplicationDocumentsDirectory();
          final clair = File('${documents.path}/packs/$documentId.json');
          if (_racine != null || !await clair.exists()) return null;
          pack = jsonDecode(await clair.readAsString()) as Map<String, dynamic>;
        }
        return _valable(pack, maintenant ?? DateTime.now());
      }
      final p = await SharedPreferences.getInstance();
      final brut = p.getString('ascenda_pack_$documentId');
      return brut == null ? null : jsonDecode(brut) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Pack illisible pour $documentId : $e');
      return null;
    }
  }

  /// Le texte intégral hors ligne a une date de validité : l'abonnement qui l'a
  /// ouvert peut prendre fin. Passé cette date, le pack garde sa fiche et ses
  /// quiz, mais plus le texte, jusqu'à la prochaine connexion.
  Map<String, dynamic> _valable(Map<String, dynamic> pack, DateTime maintenant) {
    if (pack['lecture'] == null) return pack;
    final jusqu = DateTime.tryParse('${pack['lecture_valable_jusqu_au'] ?? ''}');
    if (jusqu != null && maintenant.isAfter(jusqu)) {
      return {...pack, 'lecture': null, 'lecture_expiree': true};
    }
    return pack;
  }

  /// Le PDF d'un ouvrage, gardé chiffré pour la lecture hors ligne.
  Future<File?> _fichierPdf(String documentId) async {
    if (kIsWeb) return null;
    final base = await (_racine?.call() ?? getApplicationSupportDirectory());
    final d = Directory('${base.path}/pdf');
    if (!await d.exists()) await d.create(recursive: true);
    // Un PDF gardé en clair par une version précédente disparaît.
    final ancien = File('${d.path}/$documentId.pdf');
    if (await ancien.exists()) await ancien.delete();
    return File('${d.path}/$documentId.bin');
  }

  Future<void> enregistrerPdf(String documentId, List<int> octets) async {
    final f = await _fichierPdf(documentId);
    if (f == null) return;
    final provisoire = File('${f.path}.part');
    await provisoire.writeAsBytes(await _coffre.chiffrer(octets), flush: true);
    await provisoire.rename(f.path);
  }

  Future<Uint8List?> lirePdf(String documentId) async {
    final f = await _fichierPdf(documentId);
    if (f == null || !await f.exists()) return null;
    try {
      return await _coffre.dechiffrer(await f.readAsBytes());
    } catch (e) {
      // Altéré, ou chiffré par une autre installation : on le retélécharge.
      debugPrint('PDF hors ligne illisible pour $documentId : $e');
      await f.delete();
      return null;
    }
  }

  /// Le PDF d'un ouvrage libre, gardé tel quel.
  ///
  /// Un ouvrage libre n'a rien à cacher : le chiffrer obligerait à le relire en
  /// entier en mémoire pour l'ouvrir, ce qui coûte cher sur un gros PDF. Il vit
  /// donc en clair, dans un dossier à part de celui du coffre, et le lecteur
  /// l'ouvre page par page depuis le disque.
  Future<File?> fichierPdfClair(String documentId) async {
    if (kIsWeb) return null;
    final base = await (_racine?.call() ?? getApplicationSupportDirectory());
    final d = Directory('${base.path}/pdf/libres');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$documentId.pdf');
  }

  /// Vrai si le PDF est sur l'appareil, sous l'une ou l'autre forme.
  Future<bool> aPdf(String documentId) async {
    final f = await _fichierPdf(documentId);
    if (f != null && await f.exists()) return true;
    final clair = await fichierPdfClair(documentId);
    return clair != null && await clair.exists();
  }

  Future<void> supprimer(String documentId) async {
    final d = await _dossier();
    final pdf = await _fichierPdf(documentId);
    if (pdf != null && await pdf.exists()) await pdf.delete();
    // Le PDF en clair d'un ouvrage libre part aussi : « retirer de l'appareil »
    // doit rendre la place, quelle que soit la forme du fichier.
    final clair = await fichierPdfClair(documentId);
    if (clair != null && await clair.exists()) await clair.delete();
    if (d != null) {
      for (final nom in ['$documentId.json', '$documentId.bin']) {
        final f = File('${d.path}/$nom');
        if (await f.exists()) await f.delete();
      }
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
  final pack = await api.get('/bibliotheque/$documentId/pack') as Map<String, dynamic>;
  await depot.enregistrer(documentId, pack);
  ref.invalidate(packsProvider);
  return (await depot.index())[documentId]!;
});

/// Le pack local d'un ouvrage, s'il a été téléchargé.
final packLocalProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, documentId) async {
  return ref.watch(depotHorsLigneProvider).lire(documentId);
});


/// Un chapitre lu depuis le pack hors ligne, sous la forme que rend l'API.
///
/// Rien si le pack ne porte pas le texte de ce chapitre (ouvrage non réservé,
/// texte expiré, chapitre sans passage) : l'écran affiche alors l'erreur réseau
/// habituelle plutôt qu'une page vide.
Map<String, dynamic>? chapitreHorsLigne(Map<String, dynamic> pack, String chapitreId) {
  final lecture = (pack['lecture'] as List?)?.cast<Map<String, dynamic>>();
  if (lecture == null) return null;
  final texte = lecture.where((c) => c['chapitre_id'] == chapitreId).firstOrNull;
  if (texte == null) return null;
  final sommaire = ((pack['sommaire'] as List?) ?? []).cast<Map<String, dynamic>>();
  final i = sommaire.indexWhere((c) => c['id'] == chapitreId);
  final ch = i >= 0 ? sommaire[i] : <String, dynamic>{'id': chapitreId};
  Map<String, dynamic>? voisin(int j) =>
      j >= 0 && j < sommaire.length ? {'id': sommaire[j]['id'], 'titre': sommaire[j]['titre']} : null;
  final ouvrage = (pack['ouvrage'] as Map?)?.cast<String, dynamic>() ?? {};
  return {
    'ouvrage': {'id': ouvrage['id'], 'titre': ouvrage['titre'], 'auteurs': ouvrage['auteurs'] ?? []},
    'chapitre': {
      'id': chapitreId,
      'ordre': ch['ordre'],
      'titre': ch['titre'],
      'page_debut': ch['page_debut'],
      'page_fin': ch['page_fin'],
      'duree_min': ch['duree_min'],
    },
    'passages': [
      for (final p in ((texte['passages'] as List?) ?? []).cast<Map<String, dynamic>>())
        {
          // Pas d'identifiant de passage : surligner demande le réseau.
          'id': '',
          'page_debut': p['page_debut'],
          'page_fin': p['page_fin'],
          'texte': p['texte'],
        },
    ],
    'droits': {
      'lecture_integrale': true,
      // Le PDF s'ouvre depuis le coffre s'il a été emporté ; l'écran le vérifie.
      'pdf': true,
      'application_seulement': true,
      'tronque': false,
      'hors_ligne': true,
      'message': null,
    },
    'compte_rendu': null,
    'precedent': voisin(i - 1),
    'suivant': voisin(i + 1),
  };
}

/// La fiche d'un ouvrage emporté, reconstituée depuis son pack pour l'écran de
/// l'ouvrage. Sans réseau, c'est la porte d'entrée vers le sommaire, le texte
/// et le PDF gardés sur l'appareil.
Map<String, dynamic> ficheHorsLigne(Map<String, dynamic> pack, {bool pdf = false}) {
  final o = (pack['ouvrage'] as Map?)?.cast<String, dynamic>() ?? {};
  final integral = pack['lecture'] != null;
  final expiree = pack['lecture_expiree'] == true;
  return {
    'id': o['id'],
    'titre': o['titre'],
    'sous_titre': o['sous_titre'],
    'auteurs': o['auteurs'] ?? [],
    'annee': o['annee'],
    'editeur': o['editeur'],
    'pages': o['pages'],
    'axes': o['axes'] ?? [],
    'pedagogie': {
      'niveau': o['niveau'],
      'duree_min': o['duree_min'],
      'these_centrale': o['these_centrale'],
      'idees_force': o['idees_force'] ?? [],
    },
    'contenu': pack['compteurs'] ?? {},
    'droits': {
      'lecture_integrale': integral,
      'pdf': integral && pdf,
      'hors_ligne_integral': integral,
      'message': expiree
          ? "Le texte emporté a expiré. Reconnectez-vous une fois : ASCENDA vérifie "
              "votre abonnement et le rend lisible hors ligne pour trente jours de plus."
          : (integral ? null : (pack['droits'] as Map?)?['message']),
    },
    'hors_ligne': true,
  };
}

/// Le sommaire d'un ouvrage emporté, au format de la route `/sommaire`. Le pack
/// ne garde que les chapitres assez longs pour être lus.
List<Map<String, dynamic>> sommaireHorsLigne(Map<String, dynamic> pack) {
  final questions = <String, int>{};
  for (final q in ((pack['quiz'] as List?) ?? []).cast<Map<String, dynamic>>()) {
    final id = q['chapitre_id'] as String?;
    if (id != null) questions[id] = (questions[id] ?? 0) + ((q['questions'] as List?)?.length ?? 0);
  }
  return [
    for (final c in ((pack['sommaire'] as List?) ?? []).cast<Map<String, dynamic>>())
      {...c, 'tokens': 300, 'nb_questions': questions[c['id']] ?? 0},
  ];
}
