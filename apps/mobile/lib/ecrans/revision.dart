import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';

/// La révision espacée : une carte retournable, deux gestes.
///
/// « Je savais » éloigne la notion, « À revoir » la ramène demain. C'est tout
/// l'algorithme vu de l'utilisateur ; le reste se passe côté serveur.
class EcranRevision extends ConsumerStatefulWidget {
  const EcranRevision({super.key});

  @override
  ConsumerState<EcranRevision> createState() => _EcranRevisionState();
}

class _EcranRevisionState extends ConsumerState<EcranRevision> {
  int _index = 0;
  bool _retournee = false;
  int _sues = 0;

  Future<void> _repondre(Notion n, bool reussi, int total) async {
    setState(() {
      if (reussi) _sues++;
      _retournee = false;
      _index++;
    });
    try {
      await ref.read(clientApiProvider).post('/concepts/revision', corps: {
        'concept_id': n.conceptId,
        'reussi': reussi,
      });
    } catch (_) {
      // Une révision perdue n'est pas grave : la notion reviendra.
    }
    if (_index >= total && mounted) {
      rafraichirProgression(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notions = ref.watch(aReviserProvider);
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Révision')),
      body: notions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(aReviserProvider)),
        data: (liste) {
          if (liste.isEmpty) {
            return const EtatMessage(
              icone: Icons.check_circle_outline_rounded,
              teinte: Couleurs.sauge,
              titre: 'Rien à revoir',
              texte: "Vos notions sont à jour. Elles reviendront d'elles-mêmes "
                  "quand il sera temps.",
            );
          }
          if (_index >= liste.length) {
            return _Fin(sues: _sues, total: liste.length);
          }

          final n = liste[_index];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: LinearProgressIndicator(
                    value: (_index + 1) / liste.length,
                    minHeight: 4,
                    backgroundColor: t.colorScheme.surfaceContainer,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GestureDetector(
                    onTap: () => setState(() => _retournee = !_retournee),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Container(
                        key: ValueKey(_retournee),
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: _retournee
                              ? Couleurs.or.withValues(alpha: 0.08)
                              : t.colorScheme.surface,
                          borderRadius: BorderRadius.zero,
                          border: Border.all(
                            color: _retournee
                                ? Couleurs.or.withValues(alpha: 0.5)
                                : (t.dividerTheme.color ?? Couleurs.traitClair),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (n.axe != null)
                              Text(n.axe!,
                                  style: t.textTheme.labelSmall
                                      ?.copyWith(color: Couleurs.orTexte)),
                            const SizedBox(height: 14),
                            Text(n.terme, style: t.textTheme.headlineSmall),
                            if (_retournee) ...[
                              const Divider(height: 34),
                              Text(
                                n.definition ??
                                    "Cette notion n'a pas encore de définition dans le "
                                        "glossaire. Consultez-la dans son ouvrage d'origine.",
                                style: t.textTheme.bodyLarge?.copyWith(height: 1.68),
                              ),
                            ] else ...[
                              const SizedBox(height: 20),
                              Text(
                                'Touchez pour voir la définition.',
                                style: t.textTheme.bodySmall
                                    ?.copyWith(color: Couleurs.grisChaud),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _repondre(n, false, liste.length),
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('À revoir'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Couleurs.terracotta,
                          side: BorderSide(
                              color: Couleurs.terracotta.withValues(alpha: 0.45)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _repondre(n, true, liste.length),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Je savais'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Fin extends StatelessWidget {
  const _Fin({required this.sues, required this.total});
  final int sues;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Couleurs.sauge.withValues(alpha: 0.14),
                shape: BoxShape.rectangle,
              ),
              child: const Icon(Icons.done_all_rounded, size: 34, color: Couleurs.sauge),
            ),
            const SizedBox(height: 22),
            Text('Séance terminée', style: t.textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              '$sues notion${sues > 1 ? 's' : ''} sur $total sue'
              '${sues > 1 ? 's' : ''} du premier coup. '
              'Les autres reviendront demain.',
              style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => context.pop(),
              child: const Text('Revenir'),
            ),
          ],
        ),
      ),
    );
  }
}
