import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

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
      return Scaffold(body: EtatErreur(erreur: _erreur!, reessayer: _charger));
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
        title: Pastille('Étape ${_index + 1} sur ${questions.length}', icone: Icons.explore_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: _Etapes(total: questions.length, courante: _index),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (q['ouvrage'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Surtitre("D'après ${q['ouvrage']}"),
                    ),
                  Texte('${q['question']}', style: t.textTheme.headlineSmall?.copyWith(fontSize: 25)),
                  const SizedBox(height: 26),
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
                    const SizedBox(height: 12),
                  ],
                ],
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
                              Icon(Icons.auto_awesome_rounded, size: 18),
                            ],
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// La progression du questionnaire en segments : une étape par question, ce
/// qui dit mieux qu'une barre combien il en reste. Au delà de douze, les
/// segments deviennent trop fins et la jauge continue reprend la main.
class _Etapes extends StatelessWidget {
  const _Etapes({required this.total, required this.courante});
  final int total;
  final int courante;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (total > 12) return Jauge(valeur: (courante + 1) / total);
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
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
}

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
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: choisi ? Color.alphaBlend(p.accentVoile, p.surface) : p.surface,
        borderRadius: Rayons.carte,
        border: Border.all(color: choisi ? p.accent : p.trait, width: choisi ? 1.8 : 1),
        boxShadow: choisi ? null : p.ombreCarte,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: Rayons.carte,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                // Le témoin de sélection, rond comme un bouton radio.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: choisi ? p.accent : null,
                    border: Border.all(color: choisi ? p.accent : p.attenue.withValues(alpha: 0.5), width: 2),
                  ),
                  child: choisi ? Icon(Icons.check_rounded, size: 15, color: p.surAccent) : null,
                ),
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
      body: axes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(axesProvider)),
        data: (liste) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            SurfaceHeros(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconePastille(Icons.explore_rounded, couleur: p.accentSurHeros, taille: 50),
                  const SizedBox(height: 16),
                  Surtitre('Diagnostic', couleur: p.accentSurHeros),
                  const SizedBox(height: 6),
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
            const SizedBox(height: 26),
            for (final g in regrouperParPole(liste)) ...[
              // Un pôle ouvre une section : son nom, puis ses parcours. Six cartes
              // « Agriculture » à plat, au milieu des axes sur l'IA, se lisaient
              // comme une liste sans ordre.
              if (g.estPole) ...[
                const SizedBox(height: 14),
                TitreSection(
                  g.poleLabel!,
                  sousTitre: '${g.axes.length} parcours : choisissez celui qui répond à votre activité.',
                ),
                const SizedBox(height: 12),
              ],
              for (final a in g.axes) ...[
                _CarteAxe(axe: a, dansPole: g.estPole, onChoisi: onChoisi),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}


class _CarteAxe extends StatelessWidget {
  const _CarteAxe({required this.axe, required this.onChoisi, this.dansPole = false});
  final Axe axe;
  final bool dansPole;
  final void Function(String slug) onChoisi;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final a = axe;
    // La teinte du pôle, celle de ses couvertures ; l'or à défaut.
    final teinte = Couleurs.pole(a.poleSlug ?? a.slug) ?? p.accentTexte;
    return Opacity(
      opacity: a.parcoursPossible ? 1 : 0.55,
      child: Surface(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        // Un axe dont aucun ouvrage n'a de chapitres découpés ne peut pas donner
        // de plan : on le dit au lieu d'échouer après six questions.
        onTap: a.parcoursPossible
            ? () => onChoisi(a.slug)
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
            // La pastille teintée marque l'appartenance au pôle.
            IconePastille(
              dansPole ? Icons.route_rounded : Icons.auto_stories_rounded,
              couleur: teinte,
              taille: 44,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Texte(a.label, style: t.textTheme.titleMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Texte(
                    !a.parcoursPossible
                        ? 'Consultable, pas encore de parcours'
                        : dansPole
                            ? '${a.nbPages} pages · ${_heures(a.dureeMin)} de lecture'
                            : '${a.nbOuvrages} ouvrage${a.nbOuvrages > 1 ? 's' : ''} · ${a.nbPages} pages',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: a.parcoursPossible ? p.attenue : p.alerte,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              a.parcoursPossible ? Icons.chevron_right_rounded : Icons.hourglass_empty_rounded,
              color: p.attenue,
            ),
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
