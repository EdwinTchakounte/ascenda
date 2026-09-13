import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/cercle.dart';
import '../etat/session.dart';
import '../theme/texte.dart';

/// La barre d'onglets basse, telle que définie au design.
class CoqueAscenda extends ConsumerWidget {
  const CoqueAscenda({super.key, required this.coque});

  final StatefulNavigationShell coque;

  /// L'onglet du cercle, dont la pastille compte ce qui attend une réponse.
  static const indexCercle = 3;

  // Les libellés sont courts à dessein : sur un écran de 320 px, six onglets
  // laissent 53 px chacun, et « Bibliothèque » se coupait en deux lignes au
  // milieu d'un mot. Le titre de l'écran, lui, reste explicite.
  static const _onglets = [
    (icone: Icons.today_outlined, icoheActif: Icons.today_rounded, libelle: 'Séance'),
    (icone: Icons.local_library_outlined, icoheActif: Icons.local_library_rounded, libelle: 'Livres'),
    (icone: Icons.forum_outlined, icoheActif: Icons.forum_rounded, libelle: 'Agent'),
    (icone: Icons.diversity_3_outlined, icoheActif: Icons.diversity_3_rounded, libelle: 'Cercle'),
    (icone: Icons.insights_outlined, icoheActif: Icons.insights_rounded, libelle: 'Progrès'),
    (icone: Icons.person_outline_rounded, icoheActif: Icons.person_rounded, libelle: 'Profil'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connecte = ref.watch(sessionProvider).connecte;
    final attente = connecte ? (ref.watch(cercleMoiProvider).valueOrNull?.compteurs.total ?? 0) : 0;
    return Scaffold(
      body: coque,
      bottomNavigationBar: NavigationBar(
        selectedIndex: coque.currentIndex,
        onDestinationSelected: (i) {
          if (i == indexCercle && connecte) rafraichirCercle(ref);
          coque.goBranch(i, initialLocation: i == coque.currentIndex);
        },
        destinations: [
          for (final (i, o) in _onglets.indexed)
            NavigationDestination(
              icon: Badge(
                isLabelVisible: i == indexCercle && attente > 0,
                label: Texte('$attente'),
                child: Icon(o.icone),
              ),
              selectedIcon: Icon(o.icoheActif),
              label: o.libelle,
            ),
        ],
      ),
    );
  }
}
