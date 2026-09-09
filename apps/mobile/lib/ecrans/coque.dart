import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// La barre d'onglets basse à cinq entrées, telle que définie au design.
class CoqueAscenda extends StatelessWidget {
  const CoqueAscenda({super.key, required this.coque});

  final StatefulNavigationShell coque;

  // Les libellés sont courts à dessein : sur un écran de 320 px, cinq onglets
  // laissent 64 px chacun, et « Bibliothèque » se coupait en deux lignes au
  // milieu d'un mot. Le titre de l'écran, lui, reste explicite.
  static const _onglets = [
    (
      icone: Icons.today_outlined,
      icoheActif: Icons.today_rounded,
      libelle: 'Séance',
    ),
    (
      icone: Icons.local_library_outlined,
      icoheActif: Icons.local_library_rounded,
      libelle: 'Livres',
    ),
    (
      icone: Icons.forum_outlined,
      icoheActif: Icons.forum_rounded,
      libelle: 'Agent',
    ),
    (
      icone: Icons.insights_outlined,
      icoheActif: Icons.insights_rounded,
      libelle: 'Progrès',
    ),
    (
      icone: Icons.person_outline_rounded,
      icoheActif: Icons.person_rounded,
      libelle: 'Profil',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: coque,
      bottomNavigationBar: NavigationBar(
        selectedIndex: coque.currentIndex,
        onDestinationSelected: (i) => coque.goBranch(i, initialLocation: i == coque.currentIndex),
        destinations: [
          for (final o in _onglets)
            NavigationDestination(
              icon: Icon(o.icone),
              selectedIcon: Icon(o.icoheActif),
              label: o.libelle,
            ),
        ],
      ),
    );
  }
}
