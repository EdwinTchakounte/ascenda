import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/mouvement.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../widgets/cartes.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// Le chronogramme en vue chronologique : le cahier des séances, semaine après semaine.
class EcranChronogramme extends ConsumerWidget {
  const EcranChronogramme({super.key, required this.chronogrammeId});
  final String chronogrammeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(chronogrammeProvider(chronogrammeId));
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Texte('Mon chronogramme')),
      body: FondPapier(
        child: plan.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SqueletteCarte(lignes: 5),
          ),
          error: (e, _) => EtatErreur(
            erreur: e,
            reessayer: () => ref.invalidate(chronogrammeProvider(chronogrammeId)),
          ),
          data: (c) {
            // Regroupement par semaine : douze cartes valent mieux que soixante-dix lignes.
            final parSemaine = <String, List<Seance>>{};
            for (final s in c.seances) {
              final d = s.prevueLe ?? DateTime.now();
              final lundi = d.subtract(Duration(days: d.weekday - 1));
              parSemaine.putIfAbsent(DateFormat('yyyy-MM-dd').format(lundi), () => []).add(s);
            }
            final semaines = parSemaine.keys.toList()..sort();
            // Le rang d'entrée court d'une semaine à l'autre : la page se pose
            // ligne à ligne, puis s'arrête de compter.
            var rang = 1;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Apparition(
                  child: SurfaceHeros(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: EtiquetteCrochet('plan de lecture', couleur: p.accentSurHeros),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                CompteurAnime(
                                  (c.avancement * 100).round(),
                                  style: t.textTheme.headlineMedium?.copyWith(color: p.surHeros, height: 1),
                                ),
                                Texte(' %',
                                    style: t.textTheme.titleMedium?.copyWith(color: p.surHerosDoux)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Surtitre('Chronogramme', couleur: p.accentSurHeros),
                        const SizedBox(height: 6),
                        Texte(c.axeLabel, style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 24)),
                        const SizedBox(height: 8),
                        Texte(c.justification,
                            style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux, height: 1.6)),
                        const SizedBox(height: 18),
                        Jauge(valeur: c.avancement, piste: p.surHeros.withValues(alpha: 0.12)),
                        const SizedBox(height: 10),
                        Texte('${c.faites} séances faites sur ${c.seances.length}',
                            style: t.textTheme.labelMedium?.copyWith(color: p.surHerosDoux)),
                      ],
                    ),
                  ),
                ),

                if (c.enRetard > 0) ...[
                  const SizedBox(height: 14),
                  Apparition(
                    rang: 1,
                    child: _BandeauRetard(
                      nombre: c.enRetard,
                      premium: session.utilisateur?.aAcces('chronogramme_adaptatif') ?? false,
                      onReplanifier: () => _replanifier(context, ref),
                    ),
                  ),
                ],

                const SizedBox(height: 26),
                for (final cle in semaines) ...[
                  Apparition(
                    rang: rang < 8 ? rang++ : 8,
                    child: _EnteteSemaine(lundi: DateTime.parse(cle), seances: parSemaine[cle]!),
                  ),
                  const SizedBox(height: 12),
                  // Une feuille par semaine : les séances y sont des lignes
                  // séparées par des filets, comme un cahier réglé.
                  Surface(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < parSemaine[cle]!.length; i++)
                          Apparition(
                            rang: rang < 8 ? rang++ : 8,
                            child: _LigneSeance(
                              seance: parSemaine[cle]![i],
                              chronogrammeId: chronogrammeId,
                              derniere: i == parSemaine[cle]!.length - 1,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
                const SizedBox(height: 4),
                const Fleuron(),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _replanifier(BuildContext context, WidgetRef ref) async {
    final messager = ScaffoldMessenger.of(context);
    try {
      final j = await ref
          .read(clientApiProvider)
          .post('/chronogrammes/$chronogrammeId/replanifier') as Map<String, dynamic>;
      rafraichirProgression(ref);
      if (!context.mounted) return;
      messager.showSnackBar(
        const SnackBar(content: Texte('Plan recomposé sur les séances restantes.')),
      );
      context.pushReplacement('/chronogramme/${j['id']}');
    } on ErreurApi catch (e) {
      messager.showSnackBar(SnackBar(content: Texte(e.message)));
    } catch (_) {
      messager.showSnackBar(
        const SnackBar(content: Texte("La replanification n'a pas abouti.")),
      );
    }
  }
}

class _BandeauRetard extends StatelessWidget {
  const _BandeauRetard({
    required this.nombre,
    required this.premium,
    required this.onReplanifier,
  });

  final int nombre;
  final bool premium;
  final VoidCallback onReplanifier;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      couleur: Color.alphaBlend(p.alerte.withValues(alpha: p.sombre ? 0.14 : 0.08), p.surface),
      child: Row(
        children: [
          IconePastille(Icons.schedule_rounded, couleur: p.alerte, taille: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte(
                  nombre == 1
                      ? 'Vous avez 1 séance de retard'
                      : 'Vous avez $nombre séances de retard',
                  style: t.textTheme.titleMedium?.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 3),
                Texte(
                  premium
                      ? "Le plan peut se recomposer sur ce qu'il reste."
                      : "La replanification fait partie d'Ascension.",
                  style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Un bouton grisé dit qu'on ne peut pas, jamais comment on pourrait.
          // Pour un membre de la formule Découverte, il ouvre l'abonnement.
          TextButton(
            onPressed: premium ? onReplanifier : () => context.push('/abonnement'),
            child: Texte(premium ? 'Replanifier' : 'Débloquer'),
          ),
        ],
      ),
    );
  }
}

/// Le titre courant d'une semaine : son libellé entre crochets, un filet, et le
/// compte des séances tenues en guise de folio.
class _EnteteSemaine extends StatelessWidget {
  const _EnteteSemaine({required this.lundi, required this.seances});
  final DateTime lundi;
  final List<Seance> seances;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final dimanche = lundi.add(const Duration(days: 6));
    final memeMois = lundi.month == dimanche.month;
    final libelle = memeMois
        ? '${lundi.day} au ${dimanche.day} ${DateFormat('MMMM', 'fr_FR').format(dimanche)}'
        : '${lundi.day} ${DateFormat('MMM', 'fr_FR').format(lundi)} au '
            '${dimanche.day} ${DateFormat('MMM', 'fr_FR').format(dimanche)}';
    final faites = seances.where((s) => s.faite).length;
    final complete = faites == seances.length;

    // L'étiquette passe avant le filet.
    return LayoutBuilder(
      builder: (context, contraintes) => Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: contraintes.maxWidth > 64 ? contraintes.maxWidth - 64 : contraintes.maxWidth,
            ),
            child: EtiquetteCrochet(libelle, couleur: complete ? p.succes : p.accentTexte),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Filet()),
          const SizedBox(width: 12),
          Texte(
            '$faites/${seances.length}',
            style: t.textTheme.labelSmall?.copyWith(
              color: complete ? p.succes : p.attenue,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneSeance extends ConsumerWidget {
  const _LigneSeance({required this.seance, required this.chronogrammeId, required this.derniere});
  final Seance seance;
  final String chronogrammeId;
  final bool derniere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final aujourdhui = seance.prevueLe != null &&
        DateUtils.isSameDay(seance.prevueLe, DateTime.now());
    final passee = !seance.faite && seance.prevueLe != null && !aujourdhui &&
        seance.prevueLe!.isBefore(DateUtils.dateOnly(DateTime.now()));

    // L'état se lit à trois endroits qui disent la même chose
    final teinte = seance.faite
        ? p.succes
        : passee
            ? p.alerte
            : aujourdhui
                ? p.accentTexte
                : null;

    return Opacity(
      opacity: seance.faite ? 0.72 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              if (seance.documentId != null && seance.chapitreId != null) {
                final params = {
                  'seance': seance.id,
                  if (seance.livrable != null) 'livrable': seance.livrable!,
                  if (seance.livrableId != null) 'livrable_id': seance.livrableId!,
                  if (seance.pageDebut != null) 'page_debut': '${seance.pageDebut}',
                  if (seance.pageFin != null) 'page_fin': '${seance.pageFin}',
                }.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
                context.push('/lecture/${seance.documentId}/${seance.chapitreId}?$params');
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(
                children: [
                  // La case du cahier : cochée à l'encre quand la séance est
                  // tenue, ouverte tant qu'elle ne l'est pas.
                  _CaseACocher(
                    cochee: seance.faite,
                    couleur: teinte ?? p.attenue,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 38,
                    child: Column(
                      children: [
                        Texte(
                          seance.prevueLe == null
                              ? '-'
                              : DateFormat('E', 'fr_FR').format(seance.prevueLe!),
                          maxLines: 1,
                          style: t.textTheme.labelSmall?.copyWith(color: teinte ?? p.attenue),
                        ),
                        Texte(
                          seance.prevueLe == null ? '' : '${seance.prevueLe!.day}',
                          maxLines: 1,
                          style: t.textTheme.titleLarge?.copyWith(
                            fontSize: 19,
                            height: 1.1,
                            color: aujourdhui ? p.accentTexte : p.encre,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // L'ouvrage sur une ligne, ce qu'on y lit sur la suivante
                        Texte(
                          seance.ouvrage ?? seance.objectif,
                          style: t.textTheme.titleMedium?.copyWith(
                            fontSize: 14.5,
                            decoration: seance.faite ? TextDecoration.lineThrough : null,
                            decorationThickness: 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (seance.partie != null) ...[
                          const SizedBox(height: 1),
                          // La rature porte sur la séance entière, l'ouvrage et le
                          // chapitre
                          Texte(
                            seance.partie!,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: p.texte,
                              decoration: seance.faite ? TextDecoration.lineThrough : null,
                              decorationThickness: 1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (passee)
                              Pastille('En retard', icone: Icons.schedule_rounded, couleur: p.alerte)
                            else if (aujourdhui)
                              Pastille("Aujourd'hui", icone: Icons.play_arrow_rounded),
                            Texte(
                              [
                                dureeLisible(seance.dureeMin),
                                if (seance.pages.isNotEmpty) seance.pages,
                                if (seance.livrable == 'quiz') 'quiz',
                              ].join(' · '),
                              style: t.textTheme.labelSmall?.copyWith(color: p.attenue),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!derniere) const Filet(),
        ],
      ),
    );
  }
}

/// Une case à cocher tracée à la plume : le cadre à l'encre, et la coche par
/// dessus quand la séance est tenue.
class _CaseACocher extends StatelessWidget {
  const _CaseACocher({required this.cochee, required this.couleur});
  final bool cochee;
  final Color couleur;

  /// Le côté de la case : celui d'une case de cahier, sous le texte courant.
  static const cote = 22.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: cote,
      height: cote,
      decoration: BoxDecoration(
        color: cochee ? couleur.withValues(alpha: p.sombre ? 0.16 : 0.10) : null,
        border: Border.all(color: couleur.withValues(alpha: cochee ? 0.55 : 0.40), width: 1.3),
      ),
      child: cochee ? CustomPaint(painter: _CochePeinte(couleur)) : null,
    );
  }
}

class _CochePeinte extends CustomPainter {
  _CochePeinte(this.couleur);
  final Color couleur;

  @override
  void paint(Canvas canvas, Size t) {
    canvas.scale(t.width / 24, t.height / 24);
    final plume = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Une coche qui dépasse du cadre, comme une main la trace.
    canvas.drawPath(
      Path()
        ..moveTo(4, 12.5)
        ..lineTo(9.5, 18.5)
        ..lineTo(21, 4),
      plume,
    );
  }

  @override
  bool shouldRepaint(covariant _CochePeinte a) => a.couleur != couleur;
}
