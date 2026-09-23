import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/session.dart';
import '../theme/icones.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import 'ui.dart';

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

    final p = context.palette;
    if (compact) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: p.accentVoile,
          borderRadius: Rayons.carte,
          border: Border.all(color: p.accentTexte.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            IconeAscenda(Icone.lecteur, taille: 24, couleur: p.accentTexte),
            const SizedBox(width: 14),
            Expanded(
              child: Texte(
                texte,
                style: t.textTheme.bodySmall?.copyWith(color: p.encre, height: 1.5),
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => context.push('/connexion'),
              child: const Texte('Créer'),
            ),
          ],
        ),
      );
    }

    return SurfaceHeros(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: p.surHeros.withValues(alpha: 0.08),
                  borderRadius: Rayons.moyen,
                ),
                child: Image.asset('assets/marque/marque-512.png'),
              ),
              const SizedBox(width: 12),
              Expanded(child: Surtitre('Gratuit, sans carte bancaire', couleur: p.accentSurHeros)),
            ],
          ),
          const SizedBox(height: 14),
          Filet(couleur: p.surHeros.withValues(alpha: 0.18)),
          const SizedBox(height: 14),
          Texte(
            texte,
            style: t.textTheme.bodyMedium?.copyWith(color: p.surHeros, height: 1.6),
          ),
          const SizedBox(height: 18),
          // Empilés plutôt que côte à côte : sur un écran de 320 px, deux
          // boutons sur une ligne laissent si peu de place que « Créer
          // mon compte » se coupait en quatre lignes dans sa pastille.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/connexion'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              iconAlignment: IconAlignment.end,
              label: const Texte('Créer mon compte'),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: p.accentSurHeros),
              onPressed: () => context.push('/connexion?mode=connexion'),
              child: const Texte("J'ai déjà un compte"),
            ),
          ),
        ],
      ),
    );
  }
}
