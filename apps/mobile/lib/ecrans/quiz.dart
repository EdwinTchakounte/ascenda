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

/// Le quiz : une question à la fois, posée sur le papier, puis la correction.
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
        body: FondPapier(child: EtatErreur(erreur: _erreur!, reessayer: _charger)),
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
    final entete = [
      if (_quiz?['ouvrage'] != null) '${_quiz!['ouvrage']}',
      if (_quiz?['chapitre'] != null) '${_quiz!['chapitre']}',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: EtiquetteCrochet('question ${_index + 1} sur ${_questions.length}'),
      ),
      body: FondPapier(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Jauge(valeur: (_index + 1) / _questions.length),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
                // La page change avec la question : elle se repose, une fois,
                // à chaque tour de page.
                child: KeyedSubtree(
                  key: ValueKey(q.index),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_quiz?['chapitre'] != null) ...[
                        TitreCourant(entete, folio: 'q. ${_index + 1} / ${_questions.length}'),
                        const SizedBox(height: 20),
                      ],
                      Apparition(
                        child: Texte(q.question, style: t.textTheme.headlineSmall?.copyWith(fontSize: 24)),
                      ),
                      const SizedBox(height: 26),
                      for (var i = 0; i < q.choix.length; i++) ...[
                        Apparition(
                          rang: i + 1,
                          child: _CarteChoix(
                            lettre: _lettre(i),
                            libelle: q.choix[i],
                            etat: choisi == i ? _EtatChoix.choisi : _EtatChoix.neutre,
                            onTap: () => setState(() => _reponses[q.index] = i),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
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
                          icon: Transform.rotate(
                            angle: pi,
                            child: const IconeAscenda(Icone.fleche, taille: 18),
                          ),
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
                                  IconeAscenda(dernier ? Icone.sceau : Icone.fleche, taille: 18),
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
      body: FondPapier(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // Le résultat se pose en grand : c'est le moment qu'on retient
            // d'une séance de lecture.
            Apparition(
              echelle: true,
              child: SurfaceHeros(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                child: Column(
                  children: [
                    Illustration(
                      c.reussi ? Scene.laurier : Scene.lampe,
                      taille: 168,
                      couleur: p.surHeros.withValues(alpha: 0.85),
                      accent: p.accentSurHeros,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        CompteurAnime(
                          c.justes,
                          style: t.textTheme.headlineMedium?.copyWith(color: p.surHeros, height: 1),
                        ),
                        Texte('/${c.total}',
                            style: t.textTheme.titleMedium?.copyWith(color: p.surHerosDoux)),
                        const SizedBox(width: 14),
                        CompteurAnime(
                          (c.score * 100).round(),
                          suffixe: ' %',
                          style: t.textTheme.labelMedium?.copyWith(color: p.surHerosDoux),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Jauge(
                      valeur: part,
                      hauteur: 6,
                      piste: p.surHeros.withValues(alpha: 0.12),
                      couleur: c.reussi ? null : p.surHerosDoux,
                    ),
                    const SizedBox(height: 18),
                    EtiquetteCrochet(c.reussi ? 'bravo' : 'encore un effort',
                        couleur: p.accentSurHeros),
                    const SizedBox(height: 10),
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
            ),
            const SizedBox(height: 26),
            Apparition(
              rang: 1,
              child: TitreSection(
                'Question par question',
                sousTitre: '${c.justes} juste${c.justes > 1 ? 's' : ''}, '
                    '${c.total - c.justes} à revoir',
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < c.details.length; i++) ...[
              Apparition(
                rang: 2 + i,
                child: _CorrectionQuestion(
                  detail: c.details[i],
                  choix: _questions.where((q) => q.index == c.details[i].index).firstOrNull?.choix ??
                      const [],
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.pop(),
              icon: const IconeAscenda(Icone.signet, taille: 18),
              label: const Texte('Terminer'),
            ),
            const SizedBox(height: 26),
            const Fleuron(),
          ],
        ),
      ),
    );
  }

  static String _lettre(int i) => i < 26 ? String.fromCharCode(65 + i) : '${i + 1}';
}

/// L'état d'une carte de choix : neutre, choisie pendant le quiz, ou marquée
/// juste ou fausse dans la correction.
enum _EtatChoix { neutre, choisi, juste, faux }

/// Un choix en fiche : sa lettre dans un cadre d'encre, son libellé, et une
/// couleur qui dit son état sans qu'il faille lire la marque.
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
      _EtatChoix.choisi => p.accentTexte,
      _EtatChoix.juste => p.succes,
      _EtatChoix.faux => p.alerte,
    };
    final fond = teinte == null
        ? p.surface
        : Color.alphaBlend(teinte.withValues(alpha: p.sombre ? 0.16 : 0.09), p.surface);

    return AnimatedContainer(
      duration: Duree.bref,
      curve: courbeDouce,
      decoration: BoxDecoration(
        color: fond,
        borderRadius: Rayons.moyen,
        border: Border.all(
          color: teinte ?? p.encre.withValues(alpha: p.sombre ? 0.22 : 0.12),
          width: teinte == null ? 1 : 1.6,
        ),
        boxShadow: etat == _EtatChoix.neutre && !compact
            ? [BoxShadow(color: p.ombre.withValues(alpha: p.sombre ? 0.30 : 0.05), blurRadius: 14, offset: const Offset(0, 5))]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: Rayons.moyen,
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 15),
            child: Row(
              children: [
                // La lettre du choix, dans le cadre d'une lettrine.
                Lettrine(lettre, taille: compact ? 30 : 38, couleur: teinte ?? p.attenue),
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
                if (etat != _EtatChoix.neutre) ...[
                  const SizedBox(width: 10),
                  _MarqueEncre(juste: etat != _EtatChoix.faux, couleur: teinte!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La marque du correcteur : une coche ou une croix, tracée à la plume.
class _MarqueEncre extends StatelessWidget {
  const _MarqueEncre({required this.juste, required this.couleur, this.taille = 22});
  final bool juste;
  final Color couleur;
  final double taille;

  @override
  Widget build(BuildContext context) {
    // Le trait se pose au moment où la marque apparaît : un geste bref, une
    // seule fois.
    final rapide = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox(
      width: taille,
      height: taille,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: rapide ? Duration.zero : Duree.moyen,
        curve: courbeDouce,
        builder: (_, v, _) => CustomPaint(painter: _MarquePeinte(juste, couleur, v)),
      ),
    );
  }
}

class _MarquePeinte extends CustomPainter {
  _MarquePeinte(this.juste, this.couleur, this.avance);
  final bool juste;
  final Color couleur;
  final double avance;

  @override
  void paint(Canvas canvas, Size t) {
    canvas.scale(t.width / 24, t.height / 24);
    final plume = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final v = avance.clamp(0.0, 1.0);
    if (juste) {
      // Une coche en deux temps : la descente, puis la remontée.
      final a = Offset(4, 13), b = Offset(9.5, 18.5), c = Offset(20, 6);
      final t1 = (v / 0.4).clamp(0.0, 1.0);
      canvas.drawLine(a, Offset.lerp(a, b, t1)!, plume);
      if (v > 0.4) {
        final t2 = ((v - 0.4) / 0.6).clamp(0.0, 1.0);
        canvas.drawLine(b, Offset.lerp(b, c, t2)!, plume);
      }
    } else {
      final t1 = (v / 0.5).clamp(0.0, 1.0);
      canvas.drawLine(const Offset(6, 6), Offset.lerp(const Offset(6, 6), const Offset(18, 18), t1)!, plume);
      if (v > 0.5) {
        final t2 = ((v - 0.5) / 0.5).clamp(0.0, 1.0);
        canvas.drawLine(const Offset(18, 6), Offset.lerp(const Offset(18, 6), const Offset(6, 18), t2)!, plume);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarquePeinte a) =>
      a.juste != juste || a.couleur != couleur || a.avance != avance;
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
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: p.sombre ? 0.14 : 0.08),
                  border: Border.all(color: couleur.withValues(alpha: 0.42)),
                ),
                child: _MarqueEncre(juste: detail.juste, couleur: couleur, taille: 20),
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
            const Filet(redouble: true),
            const SizedBox(height: 14),
            // L'extrait qui fonde la réponse : une citation en exergue, avec
            // son folio, comme dans la marge d'un livre.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 2, height: 46, color: p.accentTexte.withValues(alpha: 0.55)),
                const SizedBox(width: 12),
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
                        Texte(
                          'p. ${detail.extraitPage ?? detail.page}',
                          style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 1),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
