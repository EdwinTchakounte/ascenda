import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Le coffre de l'application : ce qui ne doit se lire que dans ASCENDA.
///
/// Un ouvrage réservé à l'application (le Mémento de l'agronome) se garde hors
/// ligne, texte et PDF. Il ne doit pas pour autant devenir un fichier qu'on
/// copie et qu'on ouvre ailleurs. Il est donc chiffré en AES-256-GCM avant
/// d'être écrit, avec une clé tirée au hasard à la première utilisation et
/// rangée dans le coffre du système (Keystore sur Android, trousseau sur iOS),
/// jamais sur le disque à côté des données.
///
/// Ce que cela garantit : un fichier extrait du téléphone, par sauvegarde ou par
/// copie, est illisible sans la clé, qui ne quitte pas l'appareil. Ce que cela ne
/// garantit pas : un appareil compromis par son propriétaire (root) peut tout
/// lire. Aucune protection logicielle ne l'empêche ; celle-ci rend l'extraction
/// délibérée et difficile au lieu d'accidentelle et triviale.
class Coffre {
  Coffre({Future<List<int>> Function()? cle}) : _fournirCle = cle;

  static const _nomCle = 'ascenda_cle_hors_ligne_v1';
  static const _stockage = FlutterSecureStorage();

  final Future<List<int>> Function()? _fournirCle;
  final _algorithme = AesGcm.with256bits();
  SecretKey? _cle;

  Future<SecretKey> _laCle() async {
    if (_cle != null) return _cle!;
    if (_fournirCle != null) return _cle = SecretKey(await _fournirCle());
    final existante = await _stockage.read(key: _nomCle);
    if (existante != null) return _cle = SecretKey(base64Decode(existante));
    final hasard = Random.secure();
    final octets = List<int>.generate(32, (_) => hasard.nextInt(256));
    await _stockage.write(key: _nomCle, value: base64Encode(octets));
    return _cle = SecretKey(octets);
  }

  /// Nonce (12 octets), texte chiffré, puis code d'authentification (16 octets).
  Future<Uint8List> chiffrer(List<int> clair) async {
    final boite = await _algorithme.encrypt(clair, secretKey: await _laCle());
    return Uint8List.fromList(boite.concatenation());
  }

  /// Lève une exception si les données ont été altérées ou viennent d'une
  /// autre installation : le code d'authentification ne concorde plus.
  Future<Uint8List> dechiffrer(List<int> donnees) async {
    final boite = SecretBox.fromConcatenation(donnees, nonceLength: 12, macLength: 16);
    return Uint8List.fromList(await _algorithme.decrypt(boite, secretKey: await _laCle()));
  }

  Future<Uint8List> chiffrerTexte(String texte) => chiffrer(utf8.encode(texte));

  Future<String> dechiffrerTexte(List<int> donnees) async => utf8.decode(await dechiffrer(donnees));
}
