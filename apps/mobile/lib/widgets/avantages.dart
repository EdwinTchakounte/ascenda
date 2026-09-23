import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/icones.dart';
import '../theme/palette.dart';
import '../theme/texte.dart';

/// La bonne nouvelle, sur l'écran d'accueil : quelqu'un a créé son compte
/// avec votre code, et votre prochain abonnement coûte moins cher.
///
/// Elle reste là jusqu'à ce qu'on ouvre « Codes et avantages ». Le courriel
/// dit la même chose, mais tout le monde ne lit pas ses courriels ; tout le
/// monde ouvre l'application pour lire.
class BandeauRecompense extends ConsumerWidget {
  const BandeauRecompense({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(codesProvider).valueOrNull;
    if (c == null || c.nouveaux == 0) return const SizedBox.shrink();
    final t = Theme.of(context);
    final bons = c.nouveauxBons;
    final premier = bons.isEmpty ? null : bons.first;
    final texte = c.nouveaux == 1 && premier != null
        ? "${premier.filleul ?? 'Un lecteur'} a rejoint ASCENDA avec votre code : "
            "-${premier.pourcent} % sur votre prochain abonnement."
        : "${c.nouveaux} lecteurs ont rejoint ASCENDA avec votre code. "
            "Vos réductions vous attendent.";

    final p = context.palette;
    // Un bon posé sur la page : le filet d'or à gauche fait la souche.
    return Container(
      key: const Key('bandeau-recompense'),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(p.accentVoile, p.surface),
        borderRadius: Rayons.carte,
        border: Border.all(color: p.accentTexte.withValues(alpha: 0.30)),
        boxShadow: p.ombreCarte,
      ),
      child: Row(
        children: [
          Container(width: 3, height: 58, color: p.accentTexte.withValues(alpha: 0.55)),
          const SizedBox(width: 13),
          IconeAscenda(Icone.jeton, taille: 24, couleur: p.accentTexte),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Texte(texte,
                  style: t.textTheme.bodySmall?.copyWith(color: p.encre, height: 1.5)),
            ),
          ),
          TextButton(
            onPressed: () async {
              await context.push('/codes');
              ref.invalidate(codesProvider);
            },
            style: TextButton.styleFrom(foregroundColor: p.accentTexte),
            child: const Texte('Voir'),
          ),
        ],
      ),
    );
  }
}
