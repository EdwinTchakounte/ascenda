import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/papier.dart';
import '../widgets/etats.dart';
import '../widgets/illustrations.dart';
import '../widgets/selon_droit.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// Le diagnostic d'entrée : un questionnaire d'atelier, une question par page,
/// grande et centrée, avec ses étapes numérotées en tête.
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
        SnackBar(content: Texte('${profil['message']}')),
      );
      context.go('/chronogramme/${chrono['id']}');
    } on ErreurApi catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Texte(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Texte("Le plan n'a pas pu être créé. Réessayez.")),
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
      return Scaffold(body: FondPapier(child: EtatErreur(erreur: _erreur!, reessayer: _charger)));
    }

    final questions = _questions!;
    final q = questions[_index];
    final cle = '${q['cle']}';
    final choix = (q['choix'] as List).cast<Map<String, dynamic>>();
    final t = Theme.of(context);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        leading: _index == 0
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.go('/aujourdhui'),
              )
            : BackButton(onPressed: () => setState(() => _index--)),
        centerTitle: true,
        title: EtiquetteCrochet('étape ${_index + 1} sur ${questions.length}'),
      ),
      body: FondPapier(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: _Etapes(total: questions.length, courante: _index),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                // Une page par question : elle se pose une fois, puis laisse
                // la place à la suivante.
                child: KeyedSubtree(
                  key: ValueKey(cle),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TitreCourant(
                        q['ouvrage'] != null ? "d'après ${q['ouvrage']}" : 'questionnaire',
                        folio: 'étape ${_index + 1} / ${questions.length}',
                      ),
                      const SizedBox(height: 20),
                      Apparition(
                        child: Texte('${q['question']}',
                            style: t.textTheme.headlineSmall?.copyWith(fontSize: 25)),
                      ),
                      const SizedBox(height: 26),
                      for (var i = 0; i < choix.length; i++) ...[
                        Apparition(
                          rang: i + 1,
                          child: _CarteChoix(
                            libelle: '${choix[i]['libelle']}',
                            choisi: _reponses[cle] == choix[i]['valeur'],
                            onTap: () {
                              setState(() => _reponses[cle] = choix[i]['valeur']);
                              Future.delayed(const Duration(milliseconds: 180), () {
                                if (!mounted) return;
                                if (_index < questions.length - 1) {
                                  setState(() => _index++);
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (_index == questions.length - 1)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: p.fond,
                  border: Border(top: BorderSide(color: p.trait)),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_reponses.length < questions.length || _envoi) ? null : _terminer,
                      child: _envoi
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: p.surAccent))
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Texte('Construire mon chronogramme',
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                SizedBox(width: 8),
                                IconeAscenda(Icone.boussole, taille: 18),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// La progression du questionnaire, étape par étape : des cases numérotées,
/// encrées à mesure qu'on avance. Au delà de huit, les numéros deviennent
/// illisibles et les segments reprennent la main ; au delà de douze, la jauge
/// continue.
class _Etapes extends StatelessWidget {
  const _Etapes({required this.total, required this.courante});
  final int total;
  final int courante;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    if (total > 12) return Jauge(valeur: (courante + 1) / total);
    if (total > 8) {
      return Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: AnimatedContainer(
                duration: Duree.moyen,
                curve: courbeDouce,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: Rayons.pilule,
                  color: i <= courante ? null : p.surfaceCreuse,
                  gradient: i <= courante
                      ? LinearGradient(colors: [p.accent, p.accentSurHeros])
                      : null,
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: Duree.moyen,
            curve: courbeDouce,
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i < courante
                  ? p.accentTexte.withValues(alpha: p.sombre ? 0.20 : 0.12)
                  : (i == courante ? p.accent : null),
              border: Border.all(
                color: i <= courante ? p.accentTexte : p.encre.withValues(alpha: p.sombre ? 0.24 : 0.16),
                width: i == courante ? 1.6 : 1.2,
              ),
            ),
            child: Texte(
              '${i + 1}',
              style: t.textTheme.labelSmall?.copyWith(
                color: i == courante
                    ? p.surAccent
                    : (i < courante ? p.accentTexte : p.attenue),
                fontWeight: FontWeight.w700,
                fontFamily: t.textTheme.headlineSmall?.fontFamily,
              ),
            ),
          ),
      ],
    );
  }
}

/// Une réponse en fiche : la case d'atelier à gauche, le libellé à droite.
class _CarteChoix extends StatelessWidget {
  const _CarteChoix({required this.libelle, required this.choisi, required this.onTap});

  final String libelle;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return AnimatedContainer(
      duration: Duree.bref,
      curve: courbeDouce,
      decoration: BoxDecoration(
        color: choisi ? Color.alphaBlend(p.accentVoile, p.surface) : p.surface,
        borderRadius: Rayons.moyen,
        border: Border.all(
          color: choisi ? p.accentTexte : p.encre.withValues(alpha: p.sombre ? 0.22 : 0.12),
          width: choisi ? 1.6 : 1,
        ),
        boxShadow: choisi
            ? null
            : [BoxShadow(color: p.ombre.withValues(alpha: p.sombre ? 0.30 : 0.05), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: Rayons.moyen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                // Le témoin de sélection : une case cochée à la plume.
                _CaseAtelier(cochee: choisi),
                const SizedBox(width: 14),
                Expanded(
                  child: Texte(
                    libelle,
                    style: t.textTheme.bodyLarge?.copyWith(
                      color: p.encre,
                      fontWeight: choisi ? FontWeight.w600 : FontWeight.w400,
                      height: 1.45,
                    ),
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

/// La case d'un questionnaire d'atelier : un cadre à l'encre, coché au trait.
class _CaseAtelier extends StatelessWidget {
  const _CaseAtelier({required this.cochee});
  final bool cochee;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = cochee ? p.accentTexte : p.attenue;
    return AnimatedContainer(
      duration: Duree.bref,
      curve: courbeDouce,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: cochee ? c.withValues(alpha: p.sombre ? 0.18 : 0.11) : null,
        border: Border.all(color: c.withValues(alpha: cochee ? 0.7 : 0.45), width: 1.4),
      ),
      child: cochee ? CustomPaint(painter: _CochePeinte(c)) : null,
    );
  }
}

class _CochePeinte extends CustomPainter {
  _CochePeinte(this.couleur);
  final Color couleur;

  @override
  void paint(Canvas canvas, Size t) {
    canvas.scale(t.width / 24, t.height / 24);
    canvas.drawPath(
      Path()
        ..moveTo(4, 12.5)
        ..lineTo(9.5, 18.5)
        ..lineTo(21, 4),
      Paint()
        ..color = couleur
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CochePeinte a) => a.couleur != couleur;
}

class _ChoixAxe extends ConsumerWidget {
  const _ChoixAxe({required this.onChoisi});
  final void Function(String slug) onChoisi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final axes = ref.watch(axesProvider);
    final t = Theme.of(context);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/aujourdhui'),
        ),
      ),
      body: FondPapier(
        child: axes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(axesProvider)),
          data: (liste) {
            // Le rang d'entrée court d'un pôle à l'autre, puis s'arrête de
            // compter : la dernière carte ne doit pas se faire attendre.
            var rang = 1;
            int suivant() => rang < 7 ? rang++ : 7;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Apparition(
                  child: SurfaceHeros(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Illustration(
                            Scene.graine,
                            taille: 150,
                            couleur: p.surHeros.withValues(alpha: 0.85),
                            accent: p.accentSurHeros,
                          ),
                        ),
                        const SizedBox(height: 14),
                        EtiquetteCrochet('diagnostic', couleur: p.accentSurHeros),
                        const SizedBox(height: 10),
                        Texte('Par quoi voulez-vous commencer ?',
                            style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 25)),
                        const SizedBox(height: 8),
                        Texte(
                          "Un axe, ce n'est pas un thème : c'est un centre d'intérêt, un "
                          "objectif et le temps que vous avez. Vous pourrez en changer.",
                          style: t.textTheme.bodyMedium?.copyWith(color: p.surHerosDoux),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                for (final g in regrouperParPole(liste)) ...[
                  // Un pôle ouvre une section : son nom, puis ses parcours. Six cartes
                  // « Agriculture » à plat, au milieu des axes sur l'IA, se lisaient
                  // comme une liste sans ordre.
                  if (g.estPole) ...[
                    const SizedBox(height: 14),
                    Apparition(
                      rang: suivant(),
                      child: TitreSection(
                        g.poleLabel!,
                        sousTitre: '${g.axes.length} parcours : choisissez celui qui répond à votre activité.',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final a in g.axes) ...[
                    Apparition(
                      rang: suivant(),
                      child: _CarteAxe(axe: a, dansPole: g.estPole, onChoisi: onChoisi),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                const SizedBox(height: 14),
                const Fleuron(),
              ],
            );
          },
        ),
      ),
    );
  }
}


class _CarteAxe extends ConsumerWidget {
  const _CarteAxe({required this.axe, required this.onChoisi, this.dansPole = false});
  final Axe axe;
  final bool dansPole;
  final void Function(String slug) onChoisi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final a = axe;
    // Un parcours réservé est refusé par le serveur au moment de composer le
    // plan, c'est-à-dire après le diagnostic entier. On le dit ici.
    final reserve = a.premium && !aLeDroit(ref, 'axes_reserves');
    final ouvert = a.parcoursPossible && !reserve;
    // La teinte du pôle, celle de ses couvertures ; l'or à défaut.
    final teinte = Couleurs.pole(a.poleSlug ?? a.slug) ?? p.accentTexte;
    return Opacity(
      opacity: ouvert ? 1 : 0.55,
      child: Surface(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        // Un axe dont aucun ouvrage n'a de chapitres découpés ne peut pas donner
        // de plan : on le dit au lieu d'échouer après six questions.
        onTap: ouvert
            ? () => onChoisi(a.slug)
            : reserve
                ? () => context.push('/abonnement')
                : () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Texte(
                      "Les ouvrages de « ${a.label} » ne sont pas encore "
                      "découpés en chapitres : aucun plan de lecture ne "
                      "peut être composé. Ils restent consultables dans "
                      "la bibliothèque.",
                    ),
                    duration: const Duration(seconds: 6),
                  ),
                ),
        child: Row(
          children: [
            // Le cachet teinté marque l'appartenance au pôle.
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: teinte.withValues(alpha: p.sombre ? 0.16 : 0.10),
                border: Border.all(color: teinte.withValues(alpha: 0.42)),
              ),
              child: IconeAscenda(
                dansPole ? Icone.boussole : Icone.volumes,
                taille: 23,
                couleur: teinte,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Texte(a.label, style: t.textTheme.titleMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Texte(
                    reserve
                        ? 'Parcours réservé à Ascension'
                        : !a.parcoursPossible
                            ? 'Consultable, pas encore de parcours'
                            : dansPole
                                ? '${millier(a.nbPages)} pages · ${_heures(a.dureeMin)} de lecture'
                                : '${a.nbOuvrages} ouvrage${a.nbOuvrages > 1 ? 's' : ''} · ${millier(a.nbPages)} pages',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: reserve ? p.accentTexte : (a.parcoursPossible ? p.attenue : p.alerte),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            ouvert
                ? IconeAscenda(Icone.fleche, taille: 20, couleur: p.attenue)
                : reserve
                    ? Icon(Icons.lock_outline_rounded, color: p.accentTexte)
                    : Icon(Icons.hourglass_empty_rounded, color: p.attenue),
          ],
        ),
      ),
    );
  }

  /// Arrondie à l'heure la plus proche, comme la fiche d'axe : 214 minutes
  /// font « 4 h » sur les deux écrans, et non « 3 h » ici et « 4 h » là.
  static String _heures(int minutes) {
    final h = (minutes / 60).round();
    return minutes < 60 ? '$minutes min' : '$h h';
  }
}
