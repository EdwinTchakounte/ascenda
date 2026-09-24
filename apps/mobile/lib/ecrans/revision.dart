import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../widgets/etats.dart';
import '../widgets/illustrations.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// La révision espacée : une fiche qu'on retourne, deux gestes.
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
      body: FondPapier(
        child: notions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(aReviserProvider)),
          data: (liste) {
            if (liste.isEmpty) {
              return EtatMessage(
                scene: Scene.laurier,
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
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
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
                  // La fiche se taille sur son texte et se pose au milieu de la
                  // page. Une définition longue fait défiler la page ; une
                  // notion courte ne laisse plus un carton vide aux deux tiers.
                  child: LayoutBuilder(
                    builder: (context, contraintes) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: contraintes.maxHeight - 42),
                        child: Center(
                          child: GestureDetector(
                            onTap: () => setState(() => _retournee = !_retournee),
                            // Chaque notion est une fiche neuve : elle se pose,
                            // puis elle se retourne sur elle-même.
                            child: KeyedSubtree(
                              key: ValueKey(n.conceptId),
                              child: Apparition(
                                child: _Retournement(
                                  retournee: _retournee,
                                  recto: _FaceNotion(notion: n, retournee: false),
                                  verso: _FaceNotion(notion: n, retournee: true),
                                ),
                              ),
                            ),
                          ),
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
      ),
    );
  }
}

/// Le retournement de la fiche : une rotation autour de l'axe vertical, la
/// face arrière remise à l'endroit à mi-course.
class _Retournement extends StatelessWidget {
  const _Retournement({required this.retournee, required this.recto, required this.verso});

  final bool retournee;
  final Widget recto;
  final Widget verso;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return retournee ? verso : recto;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: retournee ? 1 : 0),
      duration: Duree.ample,
      curve: Curves.easeInOutCubic,
      builder: (context, v, _) {
        final passee = v > 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(v * pi),
          child: passee
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(pi),
                  child: verso,
                )
              : recto,
        );
      },
    );
  }
}

/// Un raccourci d'axe (« 12-agriculture-elevage ») rendu lisible.
///
/// La liste à réviser renvoie parfois l'axe sans son libellé : le numéro
/// d'ordre tombe, les traits d'union redeviennent des espaces, la première
/// lettre passe en capitale. Un libellé déjà écrit en clair n'est pas touché.
String _axeLisible(String axe) {
  if (!_raccourciAxe.hasMatch(axe)) return axe;
  final mots = axe.substring(axe.indexOf('-') + 1).replaceAll('-', ' ');
  return mots.isEmpty ? axe : '${mots[0].toUpperCase()}${mots.substring(1)}';
}

final _raccourciAxe = RegExp(r'^\d+(-[a-z0-9]+)+$');

/// Une face de la fiche : le terme au recto, la définition au verso.
class _FaceNotion extends StatelessWidget {
  const _FaceNotion({required this.notion, required this.retournee});
  final Notion notion;
  final bool retournee;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final n = notion;
    final terme = n.terme.trim();
    final initiale = terme.isEmpty ? '?' : terme.characters.first;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: retournee ? Color.alphaBlend(p.accentVoile, p.surface) : p.surface,
        borderRadius: Rayons.carte,
        border: Border.all(
          color: retournee ? p.accent.withValues(alpha: 0.55) : p.encre.withValues(alpha: p.sombre ? 0.22 : 0.12),
          width: retournee ? 1.5 : 1,
        ),
        boxShadow: p.ombreCarte,
      ),
      child: ClipRRect(
        borderRadius: Rayons.carte,
        child: Stack(
          children: [
            // Un signe en filigrane, pour que la fiche ne soit pas un
            // rectangle vide autour d'un mot.
            Positioned(
              right: -18,
              bottom: -18,
              child: IconeAscenda(
                retournee ? Icone.volumes : Icone.cartes,
                taille: 118,
                epaisseur: 1.1,
                couleur: p.accentTexte.withValues(alpha: p.sombre ? 0.09 : 0.07),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      EtiquetteCrochet(retournee ? 'définition' : 'notion'),
                      const SizedBox(width: 12),
                      if (n.axe != null)
                        Expanded(
                          child: Texte(
                            _axeLisible(n.axe!),
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 0.8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (retournee) ...[
                    Texte(terme, style: t.textTheme.headlineMedium?.copyWith(fontSize: 24)),
                    const SizedBox(height: 14),
                    const Filet(redouble: true),
                    const SizedBox(height: 16),
                    Texte(
                      n.definition ??
                          "Cette notion n'a pas encore de définition dans le "
                              "glossaire. Consultez-la dans son ouvrage d'origine.",
                      style: t.textTheme.bodyLarge?.copyWith(height: 1.68, color: p.texte),
                    ),
                    const SizedBox(height: 22),
                    const Fleuron(),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Lettrine(initiale, taille: 58),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Texte(
                            terme,
                            style: t.textTheme.headlineMedium?.copyWith(fontSize: 30, height: 1.12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Filet(redouble: true),
                    const SizedBox(height: 14),
                    // Le pied de la fiche : la consigne à gauche, le compte des
                    // passages à droite, comme un folio.
                    Row(
                      children: [
                        IconeAscenda(Icone.cartes, taille: 18, couleur: p.attenue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Texte(
                            'Touchez pour voir la définition.',
                            style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                          ),
                        ),
                        if (n.revisions > 0) ...[
                          const SizedBox(width: 10),
                          Texte(
                            n.revisions > 1 ? 'revue ${n.revisions} fois' : 'revue une fois',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 0.6),
                          ),
                        ],
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
        child: Apparition(
          echelle: true,
          child: SurfaceHeros(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Illustration(
                  Scene.laurier,
                  taille: 172,
                  couleur: p.surHeros.withValues(alpha: 0.85),
                  accent: p.accentSurHeros,
                ),
                const SizedBox(height: 16),
                EtiquetteCrochet('révision', couleur: p.accentSurHeros),
                const SizedBox(height: 10),
                Texte('Séance terminée',
                    textAlign: TextAlign.center,
                    style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 26)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    CompteurAnime(
                      sues,
                      style: t.textTheme.headlineMedium?.copyWith(color: p.surHeros, height: 1),
                    ),
                    Texte(' / $total',
                        style: t.textTheme.titleMedium?.copyWith(color: p.surHerosDoux)),
                  ],
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
      ),
    );
  }
}
