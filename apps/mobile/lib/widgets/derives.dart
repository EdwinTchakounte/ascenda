import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/icones.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import 'ui.dart';

/// L'affichage des textes qu'ASCENDA écrit sur un ouvrage.
///
/// Compte rendu de chapitre, synthèse et résumé exécutif sont nos textes, pas
/// ceux de l'auteur : ce sont des oeuvres dérivées, elles ne tombent pas sous
/// le plafond de citation qui gouverne les extraits littéraux.
///
/// Chacun est nul tant qu'il n'a pas été produit. Les blocs ci-dessous
/// disparaissent alors sans rien dire : annoncer « pas encore de synthèse » sur
/// cinquante ouvrages ferait une bibliothèque qui s'excuse.

/// Le compte rendu d'un chapitre, dans le lecteur.
class CompteRenduChapitre extends StatelessWidget {
  const CompteRenduChapitre({super.key, required this.contenu});

  final Map<String, dynamic>? contenu;

  @override
  Widget build(BuildContext context) {
    final c = contenu;
    if (c == null) return const SizedBox.shrink();
    final t = Theme.of(context);
    final p = context.palette;
    final points = (c['points_cles'] as List?)?.cast<dynamic>() ?? const [];
    final reserves = (c['reserves'] as List?)?.cast<dynamic>() ?? const [];
    final afrique = '${c['pour_le_lecteur_africain'] ?? ''}'.trim();

    // Un voile doré posé sur le papier de lecture, pas une carte blanche : le
    // compte rendu accompagne le texte sans rompre la page, dans les quatre
    // thèmes.
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 28),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: p.accentVoile,
        borderRadius: Rayons.carte,
        border: Border.all(color: p.accentTexte.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: p.accentTexte.withValues(alpha: 0.26)),
                ),
                child: IconeAscenda(Icone.cahier, taille: 18, couleur: p.accentTexte),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Texte('Ce que ce chapitre établit',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleLarge?.copyWith(fontSize: 17, color: p.encre)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Filet(redouble: true),
          const SizedBox(height: 14),
          if ('${c['resume'] ?? ''}'.isNotEmpty)
            Texte('${c['resume']}', style: t.textTheme.bodyMedium?.copyWith(height: 1.65)),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final x in points) _Puce('$x'),
          ],
          if ('${c['a_retenir'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Encadre(titre: 'À retenir', texte: '${c['a_retenir']}', icone: Icone.signet),
          ],
          if (afrique.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Encadre(
              titre: 'Depuis le continent',
              texte: afrique,
              teinte: p.succes,
              icone: Icone.pousse,
            ),
          ],
          if (reserves.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                IconeAscenda(Icone.question, taille: 15, couleur: p.alerte),
                const SizedBox(width: 6),
                Texte('Réserves',
                    style: t.textTheme.labelMedium?.copyWith(color: p.alerte, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in reserves) _Puce('$r', teinte: p.alerte),
          ],
        ],
      ),
    );
  }
}

/// La synthèse et le résumé exécutif, sur la fiche d'un ouvrage.
class SyntheseOuvrage extends StatelessWidget {
  const SyntheseOuvrage({super.key, this.synthese, this.resumeExecutif});

  final Map<String, dynamic>? synthese;
  final Map<String, dynamic>? resumeExecutif;

  @override
  Widget build(BuildContext context) {
    if (synthese == null && resumeExecutif == null) return const SizedBox.shrink();
    final t = Theme.of(context);
    final p = context.palette;
    final r = resumeExecutif;
    final s = synthese;
    final sections = (s?['resume_structure'] as List?)?.cast<dynamic>() ?? const [];
    final retenir = (s?['a_retenir'] as List?)?.cast<dynamic>() ?? const [];
    final questions = (s?['questions_ouvertes'] as List?)?.cast<dynamic>() ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r != null) ...[
          const TitreSection('En bref'),
          const SizedBox(height: 12),
          // La seule carte de mise en avant de la fiche : l'ouvrage en une
          // phrase est ce qu'on retient si l'on ne lit rien d'autre.
          SurfaceHeros(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ('${r['en_une_phrase'] ?? ''}'.isNotEmpty) ...[
                  Surtitre("L'ouvrage en une phrase", couleur: p.accentSurHeros),
                  const SizedBox(height: 10),
                  Texte('${r['en_une_phrase']}',
                      style: t.textTheme.titleLarge?.copyWith(
                        color: p.surHeros,
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                        height: 1.42,
                      )),
                ],
                if ('${r['argument'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Texte('${r['argument']}',
                      style: t.textTheme.bodyMedium?.copyWith(color: p.surHerosDoux, height: 1.65)),
                ],
                if ('${r['verdict'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: p.surHeros.withValues(alpha: 0.08),
                      borderRadius: Rayons.moyen,
                      border: Border.all(color: p.surHeros.withValues(alpha: 0.10)),
                    ),
                    child: Texte('${r['verdict']}',
                        style: t.textTheme.bodySmall?.copyWith(color: p.accentSurHeros, height: 1.6)),
                  ),
                ],
                if (r['temps_de_lecture_min'] != null) ...[
                  const SizedBox(height: 14),
                  Pastille('${r['temps_de_lecture_min']} min de lecture',
                      icone: Icons.schedule_rounded, couleur: p.surHerosDoux),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
        if (s != null) ...[
          const TitreSection('La synthèse'),
          const SizedBox(height: 12),
          Surface(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ('${s['resume_court'] ?? ''}'.isNotEmpty) ...[
                  Texte('${s['resume_court']}', style: t.textTheme.bodyMedium?.copyWith(height: 1.68)),
                  const SizedBox(height: 4),
                ],
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0 || '${s['resume_court'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Divider(height: 1, color: p.trait),
                    const SizedBox(height: 14),
                  ],
                  _Section(section: sections[i] as Map<String, dynamic>),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (retenir.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Bloc(
              titre: 'À retenir',
              icone: Icone.signet,
              teinte: p.accentTexte,
              points: [for (final x in retenir) '$x'],
            ),
          ],
          if (questions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Bloc(
              titre: 'Questions que le livre laisse ouvertes',
              icone: Icone.question,
              teinte: p.succes,
              points: [for (final q in questions) '$q'],
            ),
          ],
        ],
      ],
    );
  }
}

/// Une liste de points sous un titre et son icône, sur une surface.
class _Bloc extends StatelessWidget {
  const _Bloc({required this.titre, required this.icone, required this.teinte, required this.points});
  final String titre;
  final Icone icone;
  final Color teinte;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: teinte.withValues(alpha: p.sombre ? 0.16 : 0.09),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: teinte.withValues(alpha: 0.3)),
                ),
                child: IconeAscenda(icone, taille: 17, couleur: teinte),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Texte(titre,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Filet(),
          const SizedBox(height: 12),
          for (final x in points) _Puce(x, teinte: teinte),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});
  final Map<String, dynamic> section;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final pages = '${section['pages'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Texte('${section['section'] ?? ''}',
                  style: t.textTheme.titleLarge?.copyWith(fontSize: 16, height: 1.3)),
            ),
            // Le folio, comme en tête d'une page de livre.
            if (pages.isNotEmpty) ...[
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Texte('p. $pages',
                    style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 1)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Texte('${section['contenu'] ?? ''}', style: t.textTheme.bodyMedium?.copyWith(height: 1.65)),
      ],
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce(this.texte, {this.teinte});
  final String texte;
  final Color? teinte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Un losange d'encre plutôt qu'un point : la puce du typographe.
          Container(
            margin: const EdgeInsets.only(top: 9, right: 12, left: 2),
            width: 6,
            height: 6,
            child: Transform.rotate(
              angle: pi / 4,
              child: ColoredBox(color: teinte ?? context.palette.accentTexte),
            ),
          ),
          Expanded(
            child: Texte(texte, style: t.textTheme.bodyMedium?.copyWith(height: 1.6)),
          ),
        ],
      ),
    );
  }
}

class _Encadre extends StatelessWidget {
  const _Encadre({required this.titre, required this.texte, required this.icone, this.teinte});
  final String titre;
  final String texte;
  final Icone icone;
  final Color? teinte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final c = teinte ?? p.accentTexte;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        borderRadius: Rayons.moyen,
        color: p.surface.withValues(alpha: p.sombre ? 0.55 : 0.75),
        border: Border.all(color: c.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconeAscenda(icone, taille: 15, couleur: c),
              const SizedBox(width: 7),
              Expanded(
                child: Texte(titre.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelSmall
                        ?.copyWith(color: c, fontWeight: FontWeight.w700, letterSpacing: 1.3)),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Texte(texte, style: t.textTheme.bodyMedium?.copyWith(height: 1.6)),
        ],
      ),
    );
  }
}
