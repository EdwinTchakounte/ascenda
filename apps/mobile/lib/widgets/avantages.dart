import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';

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

    return Container(
      key: const Key('bandeau-recompense'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(15, 13, 8, 13),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Couleurs.nuit, Couleurs.nuitProfond]),
      ),
      child: Row(
        children: [
          const Icon(Icons.volunteer_activism_outlined, color: Couleurs.orClair, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Text(texte,
                style: t.textTheme.bodySmall?.copyWith(color: const Color(0xFFF4F1E8), height: 1.5)),
          ),
          TextButton(
            onPressed: () async {
              await context.push('/codes');
              ref.invalidate(codesProvider);
            },
            style: TextButton.styleFrom(foregroundColor: Couleurs.orClair),
            child: const Text('Voir'),
          ),
        ],
      ),
    );
  }
}
