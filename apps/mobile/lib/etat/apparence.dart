import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/palette.dart';

class Apparence {
  const Apparence({this.theme = automatique});

  static const automatique = 'auto';
  final String theme;

  Palette palette(Brightness systeme) => theme == automatique
      ? (systeme == Brightness.dark ? Palette.nuit : Palette.ivoire)
      : Palette.parId(theme);
}

class ApparenceNotifier extends StateNotifier<Apparence> {
  ApparenceNotifier([String? initial]) : super(Apparence(theme: initial ?? Apparence.automatique));

  static const _cle = 'ascenda_theme';

  static Future<String?> themeEnregistre() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_cle);
    } catch (_) {
      return null;
    }
  }

  Future<void> choisir(String theme) async {
    state = Apparence(theme: theme);
    final p = await SharedPreferences.getInstance();
    await p.setString(_cle, theme);
  }
}

final apparenceProvider = StateNotifierProvider<ApparenceNotifier, Apparence>((ref) => ApparenceNotifier());
