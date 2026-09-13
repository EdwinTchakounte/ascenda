import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/avantages.dart';
import '../widgets/cartes.dart';
import '../widgets/exploitation.dart';
import '../widgets/etats.dart';

/// L'écran d'accueil : ce qu'il y a à faire maintenant, et rien d'autre.
class EcranAujourdhui extends ConsumerWidget {
  const EcranAujourdhui({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donnees = ref.watch(aujourdhuiProvider);
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context);
    final prenom = session.utilisateur?.nom?.split(' ').first;

    return Scaffold(
      body: RefreshIndicator(
        color: Couleurs.or,
        onRefresh: () async => rafraichirProgression(ref),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _salutation(prenom),
                    style: t.textTheme.titleLarge?.copyWith(fontSize: 19),
                  ),
                  Text(
                    toBeginningOfSentenceCase(
                      DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now()),
                    ),
                    style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                  ),
                ],
              ),
            ),
            donnees.when(
              loading: () => const SliverPadding(
                padding: EdgeInsets.all(20),
                sliver: SliverToBoxAdapter(child: SqueletteCarte(lignes: 4)),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: EtatErreur(
                  erreur: e,
                  reessayer: () => ref.invalidate(aujourdhuiProvider),
                ),
              ),
              data: (a) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                sliver: SliverList.list(children: [
                  // Le bandeau de lancement, s'il y a lieu. Il se retire tout
                  // seul à l'échéance, sans rien à changer dans l'application.
                  const BandeauLancement(),
                  const BandeauRecompense(),
                  if (a.seance != null)
                    CarteSeance(
                      seance: a.seance!,
                      onCommencer: () => _ouvrirSeance(context, a),
                    )
                  else
                    _AucuneSeance(),
                  const SizedBox(height: 28),
                  Text('Votre semaine', style: t.textTheme.titleMedium),
                  const SizedBox(height: 14),
                  PastillesSemaine(jours: a.semaine),
                  if (a.notionsAReviser > 0) ...[
                    const SizedBox(height: 26),
                    _CarteRevision(nombre: a.notionsAReviser),
                  ],
                  const SizedBox(height: 26),
                  _RaccourcisChronogramme(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _salutation(String? prenom) {
    final h = DateTime.now().hour;
    final moment = h < 12 ? 'Bonjour' : (h < 18 ? 'Bon après-midi' : 'Bonsoir');
    return prenom == null || prenom.isEmpty ? moment : '$moment, $prenom';
  }

  void _ouvrirSeance(BuildContext context, Aujourdhui a) {
    final s = a.seance!;
    if (s.documentId != null && s.chapitreId != null) {
      final params = {
        'seance': s.id,
        if (s.livrable != null) 'livrable': s.livrable!,
        if (s.livrableId != null) 'livrable_id': s.livrableId!,
        if (s.pageDebut != null) 'page_debut': '${s.pageDebut}',
        if (s.pageFin != null) 'page_fin': '${s.pageFin}',
      }.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      context.push('/lecture/${s.documentId}/${s.chapitreId}?$params');
    } else if (s.documentId != null) {
      context.push('/ouvrage/${s.documentId}');
    }
  }
}

class _AucuneSeance extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.explore_outlined, size: 30, color: Couleurs.orTexte),
          const SizedBox(height: 14),
          Text('Aucune séance prévue', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "Créez un chronogramme et ASCENDA vous proposera chaque jour une "
            "séance de lecture à votre mesure.",
            style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push('/diagnostic'),
              child: const Text('Faire le diagnostic'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteRevision extends StatelessWidget {
  const _CarteRevision({required this.nombre});
  final int nombre;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: () => context.push('/revision'),
      borderRadius: BorderRadius.zero,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Couleurs.or.withValues(alpha: 0.09),
          borderRadius: BorderRadius.zero,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Couleurs.or.withValues(alpha: 0.18),
                shape: BoxShape.rectangle,
              ),
              child: const Icon(Icons.replay_rounded, size: 21, color: Couleurs.orTexte),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre == 1 ? '1 notion à revoir' : '$nombre notions à revoir',
                    style: t.textTheme.titleMedium?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cinq minutes suffisent.',
                    style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Couleurs.orTexte),
          ],
        ),
      ),
    );
  }
}

class _RaccourcisChronogramme extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(chronogrammesProvider);
    final t = Theme.of(context);

    return plans.when(
      loading: () => const Squelette(hauteur: 74, rayon: 18),
      error: (_, _) => const SizedBox.shrink(),
      data: (liste) {
        final actifs = liste.where((c) => c['statut'] == 'actif').toList();
        if (actifs.isEmpty) return const SizedBox.shrink();
        final c = actifs.first;
        final faites = c['faites'] as int? ?? 0;
        final total = c['seances'] as int? ?? 0;
        final retard = c['en_retard'] as int? ?? 0;

        return InkWell(
          onTap: () => context.push('/chronogramme/${c['id']}'),
          borderRadius: BorderRadius.zero,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.colorScheme.surface,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${c['axe_label']}', style: t.textTheme.titleMedium),
                    ),
                    Text(
                      '$faites / $total',
                      style: t.textTheme.labelLarge?.copyWith(color: Couleurs.orTexte),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : faites / total,
                    minHeight: 6,
                    backgroundColor: t.colorScheme.surfaceContainer,
                  ),
                ),
                if (retard > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    retard == 1
                        ? '1 séance de retard'
                        : '$retard séances de retard',
                    style: t.textTheme.bodySmall?.copyWith(color: Couleurs.terracotta),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
