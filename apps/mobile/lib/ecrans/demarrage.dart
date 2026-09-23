import 'package:flutter/material.dart';

import '../theme/couleurs.dart';
import '../theme/texte.dart';

/// L'écran des premières secondes.
///
/// Le temps de savoir si une session existe, l'application affichait l'accueil,
/// qui appelait l'API sans jeton et montrait « Session expirée » avant de
/// rediriger. Deux dixièmes de seconde d'erreur suffisent à donner le sentiment
/// d'un produit fragile.
///
/// Il garde les couleurs fixes de la marque, quel que soit le thème choisi :
/// c'est le logo qui accueille, pas encore l'application.
class EcranDemarrage extends StatelessWidget {
  const EcranDemarrage({super.key});

  @override
  Widget build(BuildContext context) {
    const nuit = Palette.nuit;
    return Scaffold(
      backgroundColor: Couleurs.marqueNuit,
      body: Stack(
        children: [
          // Une lueur dorée très basse derrière le logo, comme une lampe de
          // lecture allumée au centre de la pièce.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.75,
                    colors: [
                      Couleurs.marqueOr.withValues(alpha: 0.12),
                      Couleurs.marqueNuit.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/marque/logo-complet.png',
                  height: 148,
                  filterQuality: FilterQuality.medium,
                  semanticLabel: 'ASCENDA, Learn. Grow. Become.',
                ),
                const SizedBox(height: 26),
                // Le titre courant d'une page de livre : petites capitales
                // entre deux filets d'or.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FiletOr(largeur: 26),
                    const SizedBox(width: 12),
                    Texte(
                      'ATELIER DE LECTURE',
                      style: TextStyle(
                        color: Couleurs.marqueOr.withValues(alpha: 0.85),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.4,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _FiletOr(largeur: 26),
                  ],
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: Rayons.pilule,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: Couleurs.marqueOr,
                      backgroundColor: nuit.surHeros.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un court filet d'or, de part et d'autre du titre courant.
class _FiletOr extends StatelessWidget {
  const _FiletOr({required this.largeur});
  final double largeur;

  @override
  Widget build(BuildContext context) => Container(
        width: largeur,
        height: 1,
        color: Couleurs.marqueOr.withValues(alpha: 0.5),
      );
}
