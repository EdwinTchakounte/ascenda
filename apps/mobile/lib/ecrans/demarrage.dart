import 'package:flutter/material.dart';

import '../theme/couleurs.dart';

/// L'écran des premières secondes.
///
/// Le temps de savoir si une session existe, l'application affichait l'accueil,
/// qui appelait l'API sans jeton et montrait « Session expirée » avant de
/// rediriger. Deux dixièmes de seconde d'erreur suffisent à donner le sentiment
/// d'un produit fragile.
class EcranDemarrage extends StatelessWidget {
  const EcranDemarrage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Couleurs.nuitProfond,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/marque/logo-complet.png',
              height: 148,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'ASCENDA, Learn. Grow. Become.',
            ),
            const SizedBox(height: 36),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Couleurs.or),
            ),
          ],
        ),
      ),
    );
  }
}
