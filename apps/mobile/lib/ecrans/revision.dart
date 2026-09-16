import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/palette.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

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
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Texte('Révision')),
      body: notions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(aReviserProvider)),
        data: (liste) {
          if (liste.isEmpty) {
            return EtatMessage(
              icone: Icons.check_circle_outline_rounded,
              teinte: p.succes,
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
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    Expanded(child: Jauge(valeur: (_index + 1) / liste.length)),
                    const SizedBox(width: 12),
                    Texte('${_index + 1} / ${liste.length}',
                        style: t.textTheme.labelMedium?.copyWith(color: p.attenue, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  child: GestureDetector(
                    onTap: () => setState(() => _retournee = !_retournee),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (enfant, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.97, end: 1.0).animate(anim),
                          child: enfant,
                        ),
                      ),
                      child: _CarteNotion(
                        key: ValueKey('${n.conceptId}-$_retournee'),
                        notion: n,
                        retournee: _retournee,
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _repondre(n, false, liste.length),
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Texte('À revoir', maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.alerte,
                          side: BorderSide(color: p.alerte.withValues(alpha: 0.45)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _repondre(n, true, liste.length),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Texte('Je savais', maxLines: 1, overflow: TextOverflow.ellipsis),
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

/// La carte d'une notion : le terme au recto, la définition au verso.
class _CarteNotion extends StatelessWidget {
  const _CarteNotion({super.key, required this.notion, required this.retournee});
  final Notion notion;
  final bool retournee;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final n = notion;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: retournee ? Color.alphaBlend(p.accentVoile, p.surface) : p.surface,
        borderRadius: Rayons.grand,
        border: Border.all(color: retournee ? p.accent.withValues(alpha: 0.55) : p.trait, width: retournee ? 1.5 : 1),
        boxShadow: p.ombreCarte,
      ),
      child: ClipRRect(
        borderRadius: Rayons.grand,
        child: Stack(
          children: [
            // Un grand signe en filigrane, pour que le recto ne soit pas un
            // rectangle vide autour d'un mot.
            Positioned(
              right: -30,
              bottom: -30,
              child: Icon(
                retournee ? Icons.menu_book_rounded : Icons.lightbulb_rounded,
                size: 170,
                color: p.accentTexte.withValues(alpha: p.sombre ? 0.07 : 0.05),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconePastille(
                        retournee ? Icons.menu_book_rounded : Icons.lightbulb_rounded,
                        taille: 44,
                      ),
                      const Spacer(),
                      Pastille(retournee ? 'Définition' : 'Notion', couleur: p.attenue),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (n.axe != null) ...[
                    Surtitre(n.axe!),
                    const SizedBox(height: 8),
                  ],
                  Texte(n.terme, style: t.textTheme.headlineMedium?.copyWith(fontSize: retournee ? 24 : 30)),
                  if (retournee) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: 44,
                      height: 3,
                      decoration: BoxDecoration(color: p.accent, borderRadius: Rayons.pilule),
                    ),
                    const SizedBox(height: 16),
                    Texte(
                      n.definition ??
                          "Cette notion n'a pas encore de définition dans le "
                              "glossaire. Consultez-la dans son ouvrage d'origine.",
                      style: t.textTheme.bodyLarge?.copyWith(height: 1.68, color: p.texte),
                    ),
                  ] else ...[
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Icon(Icons.touch_app_rounded, size: 18, color: p.attenue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Texte(
                            'Touchez pour voir la définition.',
                            style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
    final p = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SurfaceHeros(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconePastille(Icons.done_all_rounded, couleur: p.accentSurHeros, taille: 72),
              const SizedBox(height: 20),
              Surtitre('Révision', couleur: p.accentSurHeros),
              const SizedBox(height: 6),
              Texte('Séance terminée',
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 26)),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$sues'),
                  TextSpan(
                    text: ' / $total',
                    style: t.textTheme.titleMedium?.copyWith(color: p.surHerosDoux),
                  ),
                ]),
                style: t.textTheme.headlineMedium?.copyWith(color: p.surHeros, height: 1),
              ),
              const SizedBox(height: 10),
              Jauge(
                valeur: total == 0 ? 0 : sues / total,
                hauteur: 6,
                piste: p.surHeros.withValues(alpha: 0.12),
              ),
              const SizedBox(height: 14),
              Texte(
                '$sues notion${sues > 1 ? 's' : ''} sur $total sue'
                '${sues > 1 ? 's' : ''} du premier coup. '
                'Les autres reviendront demain.',
                style: t.textTheme.bodyMedium?.copyWith(color: p.surHerosDoux),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.pop(),
                  child: const Texte('Revenir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
