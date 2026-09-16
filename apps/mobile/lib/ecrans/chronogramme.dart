import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/palette.dart';
import '../widgets/cartes.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// Le chronogramme en vue chronologique. Les séances faites sont en sourdine et
/// marquées en vert, celle du jour en or, les retards en terracotta.
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
      body: plan.when(
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              SurfaceHeros(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconePastille(Icons.route_rounded, couleur: p.accentSurHeros, taille: 46),
                        const Spacer(),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${(c.avancement * 100).round()}'),
                            TextSpan(
                              text: ' %',
                              style: t.textTheme.titleMedium?.copyWith(color: p.surHerosDoux),
                            ),
                          ]),
                          style: t.textTheme.headlineMedium?.copyWith(color: p.surHeros, height: 1),
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

              if (c.enRetard > 0) ...[
                const SizedBox(height: 14),
                _BandeauRetard(
                  nombre: c.enRetard,
                  premium: session.utilisateur?.aAcces('chronogramme_adaptatif') ?? false,
                  onReplanifier: () => _replanifier(context, ref),
                ),
              ],

              const SizedBox(height: 26),
              for (final cle in semaines) ...[
                _EnteteSemaine(lundi: DateTime.parse(cle), seances: parSemaine[cle]!),
                const SizedBox(height: 12),
                for (final s in parSemaine[cle]!) ...[
                  _LigneSeance(seance: s, chronogrammeId: chronogrammeId),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 16),
              ],
            ],
          );
        },
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

class _EnteteSemaine extends StatelessWidget {
  const _EnteteSemaine({required this.lundi, required this.seances});
  final DateTime lundi;
  final List<Seance> seances;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dimanche = lundi.add(const Duration(days: 6));
    final memeMois = lundi.month == dimanche.month;
    final libelle = memeMois
        ? '${lundi.day} au ${dimanche.day} ${DateFormat('MMMM', 'fr_FR').format(dimanche)}'
        : '${lundi.day} ${DateFormat('MMM', 'fr_FR').format(lundi)} au '
            '${dimanche.day} ${DateFormat('MMM', 'fr_FR').format(dimanche)}';
    final faites = seances.where((s) => s.faite).length;
    final complete = faites == seances.length;

    return Row(
      children: [
        Flexible(
          child: Surtitre(libelle, couleur: complete ? p.succes : p.accentTexte),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: p.trait)),
        const SizedBox(width: 12),
        Pastille(
          '$faites/${seances.length}',
          icone: complete ? Icons.check_rounded : null,
          couleur: complete ? p.succes : p.attenue,
        ),
      ],
    );
  }
}

class _LigneSeance extends ConsumerWidget {
  const _LigneSeance({required this.seance, required this.chronogrammeId});
  final Seance seance;
  final String chronogrammeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final aujourdhui = seance.prevueLe != null &&
        DateUtils.isSameDay(seance.prevueLe, DateTime.now());
    final passee = !seance.faite && seance.prevueLe != null && !aujourdhui &&
        seance.prevueLe!.isBefore(DateUtils.dateOnly(DateTime.now()));

    // L'état se lit à trois endroits qui disent la même chose : la puce de
    // date, la pastille et le contour. Faite en vert, du jour en or, en
    // retard en terracotta, à venir en neutre.
    final teinte = seance.faite
        ? p.succes
        : passee
            ? p.alerte
            : aujourdhui
                ? p.accent
                : null;

    return Opacity(
      opacity: seance.faite ? 0.72 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: Rayons.carte,
          boxShadow: aujourdhui ? p.ombreCarte : null,
        ),
        child: Material(
          color: aujourdhui ? Color.alphaBlend(p.accentVoile, p.surface) : p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: Rayons.carte,
            side: BorderSide(
              color: aujourdhui ? p.accent : p.trait,
              width: aujourdhui ? 1.6 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
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
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: aujourdhui
                          ? p.accent
                          : (teinte ?? p.attenue).withValues(alpha: p.sombre ? 0.16 : 0.10),
                      borderRadius: Rayons.moyen,
                    ),
                    child: Column(
                      children: [
                        Texte(
                          seance.prevueLe == null
                              ? '-'
                              : DateFormat('E', 'fr_FR').format(seance.prevueLe!),
                          maxLines: 1,
                          style: t.textTheme.labelSmall?.copyWith(
                            color: aujourdhui ? p.surAccent : (teinte ?? p.attenue),
                          ),
                        ),
                        Texte(
                          seance.prevueLe == null ? '' : '${seance.prevueLe!.day}',
                          maxLines: 1,
                          style: t.textTheme.titleLarge?.copyWith(
                            fontSize: 19,
                            height: 1.1,
                            color: aujourdhui ? p.surAccent : p.encre,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // L'ouvrage sur une ligne, ce qu'on y lit sur la suivante :
                        // un libellé d'un seul tenant coupait le chapitre sous le
                        // titre du livre.
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
                          Texte(
                            seance.partie!,
                            style: t.textTheme.bodySmall?.copyWith(color: p.texte),
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
                            if (seance.faite)
                              Pastille('Faite', icone: Icons.check_rounded, couleur: p.succes)
                            else if (passee)
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
        ),
      ),
    );
  }
}
