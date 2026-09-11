import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';

/// Le diagnostic d'entrée : une question à l'écran, grande, centrée.
///
/// Le questionnaire vient du serveur, y compris les sondes tirées des vrais
/// quiz de l'axe. Rien n'est codé en dur ici : ajouter une question se fait
/// côté API.
class DiagnosticEcran extends ConsumerStatefulWidget {
  const DiagnosticEcran({super.key, this.axe});
  final String? axe;

  @override
  ConsumerState<DiagnosticEcran> createState() => _DiagnosticEcranState();
}

class _DiagnosticEcranState extends ConsumerState<DiagnosticEcran> {
  String? _axe;
  List<Map<String, dynamic>>? _questions;
  final Map<String, dynamic> _reponses = {};
  int _index = 0;
  bool _chargement = true;
  bool _envoi = false;
  Object? _erreur;

  @override
  void initState() {
    super.initState();
    _axe = widget.axe;
    if (_axe != null) {
      _charger();
    } else {
      _chargement = false;
    }
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final api = ref.read(clientApiProvider);
      final j = await api.get('/diagnostic', auth: false, params: {'axe': _axe})
          as Map<String, dynamic>;
      setState(() {
        _questions = (j['questions'] as List).cast<Map<String, dynamic>>();
        _chargement = false;
      });
    } catch (e) {
      setState(() {
        _erreur = e;
        _chargement = false;
      });
    }
  }

  Future<void> _terminer() async {
    setState(() => _envoi = true);
    try {
      final api = ref.read(clientApiProvider);
      final profil = await api.post('/diagnostic', corps: {
        'axe': _axe,
        'reponses': _reponses,
      }) as Map<String, dynamic>;

      final chrono = await api.post('/chronogrammes', corps: {
        'axe': _axe,
        'minutes_semaine': profil['minutes_semaine'],
        'duree_seance': profil['duree_seance'],
        if (profil['echeance_jours'] != null)
          'date_cible': DateTime.now()
              .add(Duration(days: profil['echeance_jours'] as int))
              .toIso8601String()
              .substring(0, 10),
      }) as Map<String, dynamic>;

      if (!mounted) return;
      rafraichirProgression(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${profil['message']}')),
      );
      context.go('/chronogramme/${chrono['id']}');
    } on ErreurApi catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Le plan n'a pas pu être créé. Réessayez.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_axe == null) {
      return _ChoixAxe(onChoisi: (slug) {
        setState(() => _axe = slug);
        _charger();
      });
    }

    if (_chargement) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_erreur != null) {
      return Scaffold(body: EtatErreur(erreur: _erreur!, reessayer: _charger));
    }

    final questions = _questions!;
    final q = questions[_index];
    final cle = '${q['cle']}';
    final choix = (q['choix'] as List).cast<Map<String, dynamic>>();
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: _index == 0
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.go('/aujourdhui'),
              )
            : BackButton(onPressed: () => setState(() => _index--)),
        title: Text('${_index + 1} sur ${questions.length}',
            style: t.textTheme.labelLarge?.copyWith(color: Couleurs.grisChaud)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: LinearProgressIndicator(
                value: (_index + 1) / questions.length,
                minHeight: 4,
                backgroundColor: t.colorScheme.surfaceContainer,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (q['ouvrage'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        "D'après ${q['ouvrage']}",
                        style: t.textTheme.labelMedium?.copyWith(color: Couleurs.orTexte),
                      ),
                    ),
                  Text('${q['question']}', style: t.textTheme.headlineSmall),
                  const SizedBox(height: 28),
                  for (final c in choix) ...[
                    _CarteChoix(
                      libelle: '${c['libelle']}',
                      choisi: _reponses[cle] == c['valeur'],
                      onTap: () {
                        setState(() => _reponses[cle] = c['valeur']);
                        Future.delayed(const Duration(milliseconds: 180), () {
                          if (!mounted) return;
                          if (_index < questions.length - 1) {
                            setState(() => _index++);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          if (_index == questions.length - 1)
            SafeArea(
              minimum: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_reponses.length < questions.length || _envoi) ? null : _terminer,
                  child: _envoi
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2))
                      : const Text('Construire mon chronogramme'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CarteChoix extends StatelessWidget {
  const _CarteChoix({required this.libelle, required this.choisi, required this.onTap});

  final String libelle;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: choisi ? Couleurs.or.withValues(alpha: 0.1) : t.colorScheme.surface,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: choisi ? Couleurs.or : (t.dividerTheme.color ?? Couleurs.traitClair),
            width: choisi ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                libelle,
                style: t.textTheme.bodyLarge?.copyWith(
                  fontWeight: choisi ? FontWeight.w600 : FontWeight.w400,
                  height: 1.45,
                ),
              ),
            ),
            if (choisi) const Icon(Icons.check_circle_rounded, color: Couleurs.or, size: 21),
          ],
        ),
      ),
    );
  }
}

class _ChoixAxe extends ConsumerWidget {
  const _ChoixAxe({required this.onChoisi});
  final void Function(String slug) onChoisi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final axes = ref.watch(axesProvider);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/aujourdhui'),
        ),
      ),
      body: axes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(axesProvider)),
        data: (liste) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Text('Par quoi voulez-vous commencer ?', style: t.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              "Un axe, ce n'est pas un thème : c'est un centre d'intérêt, un "
              "objectif et le temps que vous avez. Vous pourrez en changer.",
              style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
            ),
            const SizedBox(height: 24),
            for (final a in liste) ...[
              Opacity(
                opacity: a.parcoursPossible ? 1 : 0.55,
                child: InkWell(
                  // Un axe dont aucun ouvrage n'a de chapitres découpés ne peut
                  // pas donner de plan : on le dit au lieu d'échouer après six
                  // questions.
                  onTap: a.parcoursPossible
                      ? () => onChoisi(a.slug)
                      : () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Les ouvrages de « ${a.label} » ne sont pas encore "
                                "découpés en chapitres : aucun plan de lecture ne "
                                "peut être composé. Ils restent consultables dans "
                                "la bibliothèque.",
                              ),
                              duration: const Duration(seconds: 6),
                            ),
                          ),
                  borderRadius: BorderRadius.zero,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: t.colorScheme.surface,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.label, style: t.textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(
                                a.parcoursPossible
                                    ? '${a.nbOuvrages} ouvrages · ${a.nbPages} pages'
                                    : 'Consultable, pas encore de parcours',
                                style: t.textTheme.bodySmall?.copyWith(
                                  color: a.parcoursPossible
                                      ? Couleurs.grisChaud
                                      : Couleurs.terracotta,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          a.parcoursPossible
                              ? Icons.chevron_right_rounded
                              : Icons.hourglass_empty_rounded,
                          color: Couleurs.grisChaud,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
