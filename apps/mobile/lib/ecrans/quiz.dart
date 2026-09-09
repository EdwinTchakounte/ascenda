import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';

/// Le quiz : une question à la fois, puis la correction.
///
/// L'écran de correction ne se contente pas de dire juste ou faux : il donne
/// l'explication et l'extrait du livre qui la fonde, avec sa page. C'est ce
/// qui distingue un quiz de lecture d'un questionnaire de culture générale.
class EcranQuiz extends ConsumerStatefulWidget {
  const EcranQuiz({super.key, required this.quizId, this.seanceId});
  final String quizId;
  final String? seanceId;

  @override
  ConsumerState<EcranQuiz> createState() => _EcranQuizState();
}

class _EcranQuizState extends ConsumerState<EcranQuiz> {
  Map<String, dynamic>? _quiz;
  List<QuestionQuiz> _questions = [];
  final Map<int, int> _reponses = {};
  int _index = 0;
  Correction? _correction;
  bool _chargement = true;
  bool _envoi = false;
  Object? _erreur;
  DateTime? _debut;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final j = await ref.read(clientApiProvider).get('/quiz/${widget.quizId}', auth: false)
          as Map<String, dynamic>;
      setState(() {
        _quiz = j;
        _questions = (j['questions'] as List)
            .map((q) => QuestionQuiz.depuisJson(q as Map<String, dynamic>))
            .toList();
        _chargement = false;
        _debut = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _erreur = e;
        _chargement = false;
      });
    }
  }

  Future<void> _corriger() async {
    setState(() => _envoi = true);
    try {
      final j = await ref.read(clientApiProvider).post(
        '/quiz/${widget.quizId}/corriger',
        corps: {
          'reponses': _reponses.map((k, v) => MapEntry('$k', v)),
          'duree_sec': _debut == null ? null : DateTime.now().difference(_debut!).inSeconds,
          if (widget.seanceId != null && widget.seanceId!.isNotEmpty)
            'session_id': widget.seanceId,
        },
      ) as Map<String, dynamic>;
      if (!mounted) return;
      rafraichirProgression(ref);
      setState(() {
        _correction = Correction.depuisJson(j);
        _envoi = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_erreur != null && _correction == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EtatErreur(erreur: _erreur!, reessayer: _charger),
      );
    }
    if (_correction != null) return _ecranCorrection();
    return _ecranQuestion();
  }

  Widget _ecranQuestion() {
    final t = Theme.of(context);
    final q = _questions[_index];
    final choisi = _reponses[q.index];
    final dernier = _index == _questions.length - 1;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('${_index + 1} sur ${_questions.length}',
            style: t.textTheme.labelLarge?.copyWith(color: Couleurs.grisChaud)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (_index + 1) / _questions.length,
                minHeight: 4,
                backgroundColor: t.colorScheme.surfaceContainer,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_quiz?['chapitre'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${_quiz!['ouvrage']} · ${_quiz!['chapitre']}',
                        style: t.textTheme.labelMedium?.copyWith(color: Couleurs.orTexte),
                      ),
                    ),
                  Text(q.question, style: t.textTheme.headlineSmall?.copyWith(fontSize: 22)),
                  const SizedBox(height: 26),
                  for (var i = 0; i < q.choix.length; i++) ...[
                    _Choix(
                      libelle: q.choix[i],
                      choisi: choisi == i,
                      onTap: () => setState(() => _reponses[q.index] = i),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            child: Row(
              children: [
                if (_index > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _index--),
                      child: const Text('Précédent'),
                    ),
                  ),
                if (_index > 0) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: choisi == null || _envoi
                        ? null
                        : dernier
                            ? _corriger
                            : () => setState(() => _index++),
                    child: _envoi
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2))
                        : Text(dernier ? 'Voir ma correction' : 'Suivant'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ecranCorrection() {
    final t = Theme.of(context);
    final c = _correction!;
    final couleur = c.reussi ? Couleurs.sauge : Couleurs.terracotta;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Correction'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${c.justes}/${c.total}',
                        style: t.textTheme.titleMedium?.copyWith(color: couleur)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.reussi ? "C'est acquis" : 'À retravailler',
                        style: t.textTheme.titleLarge?.copyWith(fontSize: 19),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.reussi
                            ? "Vous avez bien lu. Les notions ratées reviendront quand même en révision."
                            : "Les notions manquées reviennent en révision espacée dans quelques jours.",
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: Couleurs.grisChaud, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (final d in c.details) ...[
            _CorrectionQuestion(detail: d),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => context.pop(),
            child: const Text('Terminer'),
          ),
        ],
      ),
    );
  }
}

class _Choix extends StatelessWidget {
  const _Choix({required this.libelle, required this.choisi, required this.onTap});
  final String libelle;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: choisi ? Couleurs.or.withValues(alpha: 0.1) : t.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: choisi ? Couleurs.or : (t.dividerTheme.color ?? Couleurs.traitClair),
            width: choisi ? 1.8 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(libelle, style: t.textTheme.bodyLarge?.copyWith(height: 1.5)),
            ),
            if (choisi) ...[
              const SizedBox(width: 10),
              const Icon(Icons.check_circle_rounded, color: Couleurs.or, size: 21),
            ],
          ],
        ),
      ),
    );
  }
}

class _CorrectionQuestion extends StatelessWidget {
  const _CorrectionQuestion({required this.detail});
  final CorrectionQuestion detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final couleur = detail.juste ? Couleurs.sauge : Couleurs.terracotta;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                detail.juste ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: couleur,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(detail.question,
                    style: t.textTheme.titleMedium?.copyWith(fontSize: 15, height: 1.4)),
              ),
            ],
          ),
          if (detail.explication != null) ...[
            const SizedBox(height: 12),
            Text(
              detail.explication!,
              style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud, height: 1.6),
            ),
          ],
          if (detail.extrait != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(13),
                border: Border(
                  left: BorderSide(color: Couleurs.or.withValues(alpha: 0.6), width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '« ${detail.extrait!} »',
                    style: t.textTheme.bodySmall?.copyWith(
                      height: 1.6,
                      fontFamily: t.textTheme.headlineSmall?.fontFamily,
                      fontSize: 13.5,
                    ),
                  ),
                  if (detail.extraitPage != null || detail.page != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'p. ${detail.extraitPage ?? detail.page}',
                      style: t.textTheme.labelSmall?.copyWith(color: Couleurs.orTexte),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
