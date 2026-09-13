import 'package:flutter/material.dart';

import '../theme/couleurs.dart';
import '../theme/texte.dart';

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
    final points = (c['points_cles'] as List?)?.cast<dynamic>() ?? const [];
    final reserves = (c['reserves'] as List?)?.cast<dynamic>() ?? const [];
    final afrique = '${c['pour_le_lecteur_africain'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Couleurs.or.withValues(alpha: 0.07),
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize_outlined, size: 19, color: Couleurs.orTexte),
              const SizedBox(width: 9),
              Texte('Ce que ce chapitre établit',
                  style: t.textTheme.titleSmall?.copyWith(color: Couleurs.orTexte)),
            ],
          ),
          const SizedBox(height: 12),
          if ('${c['resume'] ?? ''}'.isNotEmpty)
            Texte('${c['resume']}', style: t.textTheme.bodyMedium?.copyWith(height: 1.65)),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final p in points) _Puce('$p'),
          ],
          if ('${c['a_retenir'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Encadre(titre: 'À retenir', texte: '${c['a_retenir']}'),
          ],
          if (afrique.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Encadre(
              titre: 'Depuis le continent',
              texte: afrique,
              teinte: Couleurs.sauge,
            ),
          ],
          if (reserves.isNotEmpty) ...[
            const SizedBox(height: 14),
            Texte('Réserves',
                style: t.textTheme.labelMedium?.copyWith(color: Couleurs.terracotta)),
            const SizedBox(height: 6),
            for (final r in reserves) _Puce('$r', teinte: Couleurs.terracotta),
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
    final r = resumeExecutif;
    final s = synthese;
    final sections = (s?['resume_structure'] as List?)?.cast<dynamic>() ?? const [];
    final retenir = (s?['a_retenir'] as List?)?.cast<dynamic>() ?? const [];
    final questions = (s?['questions_ouvertes'] as List?)?.cast<dynamic>() ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r != null) ...[
          Texte('En bref', style: t.textTheme.titleLarge),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Couleurs.nuit, Couleurs.ardoise]),
              borderRadius: BorderRadius.zero,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ('${r['en_une_phrase'] ?? ''}'.isNotEmpty)
                  Texte('${r['en_une_phrase']}',
                      style: t.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFF4F1E8),
                        height: 1.5,
                      )),
                if ('${r['argument'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Texte('${r['argument']}',
                      style: t.textTheme.bodyMedium
                          ?.copyWith(color: const Color(0xFFB9C1D6), height: 1.65)),
                ],
                if ('${r['verdict'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Texte('${r['verdict']}',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: Couleurs.orClair,
                        height: 1.6,
                      )),
                ],
                if (r['temps_de_lecture_min'] != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 15, color: Color(0xFF8E99B4)),
                      const SizedBox(width: 7),
                      Texte('${r['temps_de_lecture_min']} min de lecture',
                          style: t.textTheme.labelSmall
                              ?.copyWith(color: const Color(0xFF8E99B4))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),
        ],
        if (s != null) ...[
          Texte('La synthèse', style: t.textTheme.titleLarge),
          const SizedBox(height: 10),
          if ('${s['resume_court'] ?? ''}'.isNotEmpty)
            Texte('${s['resume_court']}',
                style: t.textTheme.bodyMedium?.copyWith(height: 1.68)),
          for (final sec in sections) ...[
            const SizedBox(height: 18),
            _Section(section: sec as Map<String, dynamic>),
          ],
          if (retenir.isNotEmpty) ...[
            const SizedBox(height: 20),
            Texte('À retenir', style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final x in retenir) _Puce('$x'),
          ],
          if (questions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Texte('Questions que le livre laisse ouvertes', style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final q in questions) _Puce('$q', teinte: Couleurs.sauge),
          ],
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});
  final Map<String, dynamic> section;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pages = '${section['pages'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Texte('${section['section'] ?? ''}', style: t.textTheme.titleSmall),
            ),
            if (pages.isNotEmpty)
              Texte('p. $pages',
                  style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
          ],
        ),
        const SizedBox(height: 5),
        Texte('${section['contenu'] ?? ''}',
            style: t.textTheme.bodyMedium?.copyWith(height: 1.65)),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7, right: 10),
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: teinte ?? Couleurs.orTexte,
              shape: BoxShape.rectangle,
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
  const _Encadre({required this.titre, required this.texte, this.teinte});
  final String titre;
  final String texte;
  final Color? teinte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = teinte ?? Couleurs.orTexte;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        border: Border(left: BorderSide(color: c, width: 3)),
        color: c.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Texte(titre, style: t.textTheme.labelMedium?.copyWith(color: c)),
          const SizedBox(height: 5),
          Texte(texte, style: t.textTheme.bodyMedium?.copyWith(height: 1.6)),
        ],
      ),
    );
  }
}
