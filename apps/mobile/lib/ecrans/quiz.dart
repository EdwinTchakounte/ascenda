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
    final p = context.palette;
    final q = _questions[_index];
    final choisi = _reponses[q.index];
    final dernier = _index == _questions.length - 1;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: Pastille('Question ${_index + 1} sur ${_questions.length}', icone: Icons.quiz_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Jauge(valeur: (_index + 1) / _questions.length),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_quiz?['chapitre'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Surtitre(
                        '${_quiz!['ouvrage']} · ${_quiz!['chapitre']}',
                      ),
                    ),
                  Texte(q.question, style: t.textTheme.headlineSmall?.copyWith(fontSize: 24)),
                  const SizedBox(height: 26),
                  for (var i = 0; i < q.choix.length; i++) ...[
                    _CarteChoix(
                      lettre: _lettre(i),
                      libelle: q.choix[i],
                      etat: choisi == i ? _EtatChoix.choisi : _EtatChoix.neutre,
                      onTap: () => setState(() => _reponses[q.index] = i),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.fond,
              border: Border(top: BorderSide(color: p.trait)),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Row(
                children: [
                  if (_index > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _index--),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Texte('Précédent', maxLines: 1, overflow: TextOverflow.ellipsis),
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
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: p.surAccent))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Texte(
                                    dernier ? 'Voir ma correction' : 'Suivant',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(dernier ? Icons.done_all_rounded : Icons.arrow_forward_rounded, size: 18),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ecranCorrection() {
    final t = Theme.of(context);
    final p = context.palette;
    final c = _correction!;
    final part = c.total == 0 ? 0.0 : c.justes / c.total;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Texte('Correction'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SurfaceHeros(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
            child: Column(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: part,
                          strokeWidth: 10,
                          strokeCap: StrokeCap.round,
                          color: c.reussi ? p.accentSurHeros : p.surHerosDoux,
                          backgroundColor: p.surHeros.withValues(alpha: 0.12),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: '${c.justes}'),
                              TextSpan(
                                text: '/${c.total}',
                                style: t.textTheme.titleMedium?.copyWith(color: p.surHerosDoux),
                              ),
                            ]),
                            style: t.textTheme.headlineMedium?.copyWith(color: p.surHeros, height: 1),
                          ),
                          const SizedBox(height: 4),
                          Texte('${(c.score * 100).round()} %',
                              style: t.textTheme.labelMedium?.copyWith(color: p.surHerosDoux)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Surtitre(c.reussi ? 'Bravo' : 'Encore un effort', couleur: p.accentSurHeros),
                const SizedBox(height: 6),
                Texte(
                  c.reussi ? "C'est acquis" : 'À retravailler',
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 25),
                ),
                const SizedBox(height: 8),
                Texte(
                  c.reussi
                      ? "Vous avez bien lu. Les notions ratées reviendront quand même en révision."
                      : "Les notions manquées reviennent en révision espacée dans quelques jours.",
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium?.copyWith(color: p.surHerosDoux, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          TitreSection(
            'Question par question',
            sousTitre: '${c.justes} juste${c.justes > 1 ? 's' : ''}, '
                '${c.total - c.justes} à revoir',
          ),
          const SizedBox(height: 12),
          for (final d in c.details) ...[
            _CorrectionQuestion(
              detail: d,
              choix: _questions.where((q) => q.index == d.index).firstOrNull?.choix ?? const [],
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Texte('Terminer'),
          ),
        ],
      ),
    );
  }

  static String _lettre(int i) => i < 26 ? String.fromCharCode(65 + i) : '${i + 1}';
}

/// L'état d'une carte de choix : neutre, choisie pendant le quiz, ou marquée
/// juste ou fausse dans la correction.
enum _EtatChoix { neutre, choisi, juste, faux }

/// Un choix en carte arrondie : sa lettre dans une puce, son libellé, et une
/// couleur qui dit son état sans qu'il faille lire l'icône.
class _CarteChoix extends StatelessWidget {
  const _CarteChoix({
    required this.lettre,
    required this.libelle,
    required this.etat,
    this.onTap,
    this.compact = false,
  });

  final String lettre;
  final String libelle;
  final _EtatChoix etat;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final teinte = switch (etat) {
      _EtatChoix.neutre => null,
      _EtatChoix.choisi => p.accent,
      _EtatChoix.juste => p.succes,
      _EtatChoix.faux => p.alerte,
    };
    final icone = switch (etat) {
      _EtatChoix.neutre => null,
      _EtatChoix.choisi => Icons.check_circle_rounded,
      _EtatChoix.juste => Icons.check_circle_rounded,
      _EtatChoix.faux => Icons.cancel_rounded,
    };
    final fond = teinte == null
        ? p.surface
        : Color.alphaBlend(teinte.withValues(alpha: p.sombre ? 0.16 : 0.10), p.surface);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: fond,
        borderRadius: Rayons.carte,
        border: Border.all(color: teinte ?? p.trait, width: teinte == null ? 1 : 1.8),
        boxShadow: etat == _EtatChoix.neutre && !compact ? p.ombreCarte : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: Rayons.carte,
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 15),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: compact ? 30 : 36,
                  height: compact ? 30 : 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: teinte ?? p.surfaceCreuse,
                    borderRadius: Rayons.petit,
                  ),
                  child: Texte(
                    lettre,
                    style: t.textTheme.titleSmall?.copyWith(
                      color: teinte == null
                          ? p.attenue
                          : (etat == _EtatChoix.choisi ? p.surAccent : p.surface),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 12 : 14),
                Expanded(
                  child: Texte(
                    libelle,
                    style: (compact ? t.textTheme.bodyMedium : t.textTheme.bodyLarge)?.copyWith(
                      height: 1.45,
                      color: p.encre,
                      fontWeight: etat == _EtatChoix.neutre ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                ),
                if (icone != null) ...[
                  const SizedBox(width: 10),
                  Icon(icone, color: etat == _EtatChoix.choisi ? p.accentTexte : teinte, size: 22),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CorrectionQuestion extends StatelessWidget {
  const _CorrectionQuestion({required this.detail, required this.choix});
  final CorrectionQuestion detail;

  /// Les choix de la question, tels que chargés avec le quiz : ils permettent
  /// de rappeler la réponse donnée et la bonne sans nouvel appel.
  final List<String> choix;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final couleur = detail.juste ? p.succes : p.alerte;
    String? libelle(int? i) => i != null && i >= 0 && i < choix.length ? choix[i] : null;
    final donnee = libelle(detail.votreReponse);
    final bonne = libelle(detail.bonneReponse);

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconePastille(
                detail.juste ? Icons.check_rounded : Icons.close_rounded,
                couleur: couleur,
                taille: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Texte(detail.question,
                      style: t.textTheme.titleMedium?.copyWith(fontSize: 15, height: 1.4)),
                ),
              ),
            ],
          ),
          if (donnee != null && !detail.juste) ...[
            const SizedBox(height: 14),
            _CarteChoix(
              lettre: _EcranQuizState._lettre(detail.votreReponse!),
              libelle: donnee,
              etat: _EtatChoix.faux,
              compact: true,
            ),
          ],
          if (bonne != null) ...[
            SizedBox(height: donnee != null && !detail.juste ? 8 : 14),
            _CarteChoix(
              lettre: _EcranQuizState._lettre(detail.bonneReponse!),
              libelle: bonne,
              etat: _EtatChoix.juste,
              compact: true,
            ),
          ],
          if (detail.explication != null) ...[
            const SizedBox(height: 14),
            Texte(
              detail.explication!,
              style: t.textTheme.bodyMedium?.copyWith(color: p.texte, height: 1.6),
            ),
          ],
          if (detail.extrait != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: p.surfaceCreuse,
                borderRadius: Rayons.moyen,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded, size: 20, color: p.accentTexte),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Texte(
                          '« ${detail.extrait!} »',
                          style: t.textTheme.bodySmall?.copyWith(
                            height: 1.6,
                            color: p.texte,
                            fontFamily: t.textTheme.headlineSmall?.fontFamily,
                            fontSize: 13.5,
                          ),
                        ),
                        if (detail.extraitPage != null || detail.page != null) ...[
                          const SizedBox(height: 8),
                          Pastille('p. ${detail.extraitPage ?? detail.page}', icone: Icons.menu_book_rounded),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
