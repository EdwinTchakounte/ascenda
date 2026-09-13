import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/session.dart';
import '../theme/couleurs.dart';

/// L'invitation à ouvrir un compte, montrée aux visiteurs seulement.
///
/// La bibliothèque et les fiches sont consultables sans compte : c'est la
/// vitrine du produit. Mais rien n'invitait à s'inscrire une fois sur place, et
/// un visiteur qui trouve un ouvrage intéressant n'avait aucun chemin vers la
/// suite. Ce bloc est ce chemin.
///
/// Il ne s'affiche jamais à un utilisateur connecté, et jamais tant que l'état
/// de la session n'est pas établi : un bandeau qui apparaît puis disparaît au
/// démarrage donne le sentiment d'une application mal finie.
class InvitationCompte extends ConsumerWidget {
  const InvitationCompte({super.key, this.compact = false, this.raison});

  final bool compact;

  /// Ce que l'utilisateur gagnerait, formulé pour l'écran où il se trouve.
  final String? raison;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session.etat != EtatSession.deconnecte) return const SizedBox.shrink();

    final t = Theme.of(context);
    final texte = raison ??
        "Créez votre compte et ASCENDA construit votre plan de lecture : des "
            "séances datées, des quiz corrigés, un agent qui cite ses sources.";

    if (compact) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: Couleurs.or.withValues(alpha: 0.09),
          borderRadius: BorderRadius.zero,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                texte,
                style: t.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => context.push('/connexion'),
              child: const Text('Créer'),
            ),
          ],
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Couleurs.nuit, Couleurs.nuitProfond],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                color: Couleurs.or.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset('assets/marque/marque-512.png', width: 26, height: 26),
                    const SizedBox(width: 10),
                    Text(
                      'Gratuit, sans carte bancaire',
                      style: t.textTheme.labelSmall?.copyWith(
                        color: Couleurs.orClair,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  texte,
                  style: t.textTheme.bodyMedium
                      ?.copyWith(color: const Color(0xFFD5DBEA), height: 1.6),
                ),
                const SizedBox(height: 16),
                // Empilés plutôt que côte à côte : sur un écran de 320 px, deux
                // boutons sur une ligne laissent si peu de place que « Créer
                // mon compte » se coupait en quatre lignes dans sa pastille.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.push('/connexion'),
                    child: const Text('Créer mon compte'),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/connexion?mode=connexion'),
                    child: const Text("J'ai déjà un compte"),
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
