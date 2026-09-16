import 'package:flutter/material.dart';

import '../theme/palette.dart';
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
              IconePastille(Icons.summarize_outlined, taille: 34, fond: p.surface.withValues(alpha: 0.7)),
              const SizedBox(width: 12),
              Expanded(
                child: Texte('Ce que ce chapitre établit',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleLarge?.copyWith(fontSize: 17, color: p.encre)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if ('${c['resume'] ?? ''}'.isNotEmpty)
            Texte('${c['resume']}', style: t.textTheme.bodyMedium?.copyWith(height: 1.65)),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final x in points) _Puce('$x'),
          ],
          if ('${c['a_retenir'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Encadre(titre: 'À retenir', texte: '${c['a_retenir']}', icone: Icons.push_pin_outlined),
          ],
          if (afrique.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Encadre(
              titre: 'Depuis le continent',
              texte: afrique,
              teinte: p.succes,
              icone: Icons.public_rounded,
            ),
          ],
          if (reserves.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 15, color: p.alerte),
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
              icone: Icons.push_pin_outlined,
              teinte: p.accentTexte,
              points: [for (final x in retenir) '$x'],
            ),
          ],
          if (questions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Bloc(
              titre: 'Questions que le livre laisse ouvertes',
              icone: Icons.help_outline_rounded,
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
  final IconData icone;
  final Color teinte;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Surface(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconePastille(icone, couleur: teinte, taille: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Texte(titre,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
              ),
            ],
          ),
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
            if (pages.isNotEmpty) ...[
              const SizedBox(width: 10),
              Pastille('p. $pages', couleur: p.attenue),
            ],
          ],
        ),
        const SizedBox(height: 6),
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
          Container(
            margin: const EdgeInsets.only(top: 8, right: 12, left: 2),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: teinte ?? context.palette.accentTexte,
              shape: BoxShape.circle,
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
  final IconData icone;
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
              Icon(icone, size: 15, color: c),
              const SizedBox(width: 6),
              Expanded(
                child: Texte(titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Texte(texte, style: t.textTheme.bodyMedium?.copyWith(height: 1.6)),
        ],
      ),
    );
  }
}
