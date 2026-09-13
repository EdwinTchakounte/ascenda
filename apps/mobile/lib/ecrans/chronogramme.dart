import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/cartes.dart';
import '../widgets/etats.dart';
import '../theme/texte.dart';

/// Le chronogramme en vue chronologique. Les séances passées sont en sourdine,
/// celle du jour en or, les suivantes en contour.
class EcranChronogramme extends ConsumerWidget {
  const EcranChronogramme({super.key, required this.chronogrammeId});
  final String chronogrammeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(chronogrammeProvider(chronogrammeId));
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context);

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
              Texte(c.axeLabel, style: t.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Texte(c.justification,
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: Couleurs.grisChaud, height: 1.6)),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.zero,
                child: LinearProgressIndicator(
                  value: c.avancement,
                  minHeight: 7,
                  backgroundColor: t.colorScheme.surfaceContainer,
                ),
              ),
              const SizedBox(height: 8),
              Texte('${c.faites} séances faites sur ${c.seances.length}',
                  style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),

              if (c.enRetard > 0) ...[
                const SizedBox(height: 18),
                _BandeauRetard(
                  nombre: c.enRetard,
                  premium: session.utilisateur?.aAcces('chronogramme_adaptatif') ?? false,
                  onReplanifier: () => _replanifier(context, ref),
                ),
              ],

              const SizedBox(height: 24),
              for (final cle in semaines) ...[
                _EnteteSemaine(lundi: DateTime.parse(cle)),
                const SizedBox(height: 10),
                for (final s in parSemaine[cle]!) ...[
                  _LigneSeance(seance: s, chronogrammeId: chronogrammeId),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 18),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Couleurs.terracotta.withValues(alpha: 0.09),
        borderRadius: BorderRadius.zero,
      ),
      child: Row(
        children: [
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
                  style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
  const _EnteteSemaine({required this.lundi});
  final DateTime lundi;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dimanche = lundi.add(const Duration(days: 6));
    final memeMois = lundi.month == dimanche.month;
    final libelle = memeMois
        ? '${lundi.day} au ${dimanche.day} ${DateFormat('MMMM', 'fr_FR').format(dimanche)}'
        : '${lundi.day} ${DateFormat('MMM', 'fr_FR').format(lundi)} au '
            '${dimanche.day} ${DateFormat('MMM', 'fr_FR').format(dimanche)}';

    return Row(
      children: [
        Texte(
          libelle,
          style: t.textTheme.labelLarge?.copyWith(color: Couleurs.orTexte, fontSize: 12.5),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: t.dividerTheme.color)),
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
    final aujourdhui = seance.prevueLe != null &&
        DateUtils.isSameDay(seance.prevueLe, DateTime.now());
    final passee = !seance.faite && seance.prevueLe != null && !aujourdhui &&
        seance.prevueLe!.isBefore(DateUtils.dateOnly(DateTime.now()));

    return Opacity(
      opacity: seance.faite ? 0.6 : 1,
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
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: aujourdhui
                ? Couleurs.or.withValues(alpha: 0.09)
                : t.colorScheme.surface,
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: aujourdhui
                  ? Couleurs.or
                  : (t.dividerTheme.color ?? Couleurs.traitClair),
              width: aujourdhui ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Column(
                  children: [
                    Texte(
                      seance.prevueLe == null
                          ? '-'
                          : DateFormat('E', 'fr_FR').format(seance.prevueLe!),
                      style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud),
                    ),
                    Texte(
                      seance.prevueLe == null ? '' : '${seance.prevueLe!.day}',
                      style: t.textTheme.titleMedium?.copyWith(
                        color: aujourdhui ? Couleurs.orTexte : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  color: seance.faite
                      ? Couleurs.sauge
                      : passee
                          ? Couleurs.terracotta
                          : aujourdhui
                              ? Couleurs.or
                              : t.colorScheme.surfaceContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte(
                      seance.objectif,
                      style: t.textTheme.bodyMedium?.copyWith(
                        decoration: seance.faite ? TextDecoration.lineThrough : null,
                        decorationThickness: 1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Texte(
                      [
                        dureeLisible(seance.dureeMin),
                        if (seance.pages.isNotEmpty) seance.pages,
                        if (seance.livrable == 'quiz') 'quiz',
                      ].join(' · '),
                      style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
