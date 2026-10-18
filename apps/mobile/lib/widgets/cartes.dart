import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/modeles.dart';
import '../theme/couleurs.dart';
import '../theme/texte.dart';
import '../theme/icones.dart';
import '../theme/papier.dart';
import 'livre.dart';
import 'ui.dart';

String dureeLisible(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

const niveaux = {
  'debutant': 'Débutant',
  'intermediaire': 'Intermédiaire',
  'avance': 'Avancé',
};

class CarteSeance extends StatelessWidget {
  const CarteSeance({super.key, required this.seance, this.onCommencer});

  final Seance seance;
  final VoidCallback? onCommencer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final titre = seance.ouvrage ?? 'Séance de lecture';
    return Surface(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      rayon: Rayons.moyen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EtiquetteCrochet(seance.enRetard ? 'séance en retard' : 'séance du jour',
                  couleur: seance.enRetard ? p.alerte : p.accentTexte),
              const Spacer(),
              Texte(dureeLisible(seance.dureeMin),
                  style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DosLivre(titre: titre, hauteur: 132, largeur: 44, marque: true),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte(
                      titre,
                      style: t.textTheme.headlineSmall?.copyWith(fontSize: 23, height: 1.18),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (seance.sousTitre != null) ...[
                      const SizedBox(height: 6),
                      Texte(
                        seance.sousTitre!,
                        style: t.textTheme.bodyMedium?.copyWith(color: p.attenue),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Filet(redouble: true),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        if (seance.pages.isNotEmpty) _Etiquette(icone: Icone.page, texte: seance.pages),
                        if (seance.livrable == 'quiz') const _Etiquette(icone: Icone.question, texte: 'puis un quiz'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCommencer,
              icon: const IconeAscenda(Icone.fleche, taille: 20, couleur: Color(0xFF1A1400)),
              iconAlignment: IconAlignment.end,
              label: const Texte('Ouvrir le livre'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Etiquette extends StatelessWidget {
  const _Etiquette({required this.icone, required this.texte});

  final Icone icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconeAscenda(icone, taille: 17, couleur: p.accentTexte),
        const SizedBox(width: 7),
        Texte(texte, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: p.texte)),
      ],
    );
  }
}

class CarteOuvrage extends StatelessWidget {
  const CarteOuvrage({super.key, required this.ouvrage, this.onTap});

  final Ouvrage ouvrage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final reperes = [
      if (ouvrage.niveau != null) niveaux[ouvrage.niveau] ?? ouvrage.niveau!,
      if (ouvrage.dureeMin != null) dureeLisible(ouvrage.dureeMin!),
    ];
    return Surface(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DosLivre(titre: ouvrage.titre, axeSlug: ouvrage.axeSlug, hauteur: 104, largeur: 48),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Texte(
                        ouvrage.titre,
                        style: t.textTheme.titleLarge?.copyWith(fontSize: 16.5, height: 1.28),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Texte(
                        ouvrage.auteursCourt + (ouvrage.annee != null ? ' · ${ouvrage.annee}' : ''),
                        style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (ouvrage.these != null) ...[
                        const SizedBox(height: 8),
                        Texte(
                          ouvrage.these!,
                          style: t.textTheme.bodySmall?.copyWith(height: 1.55),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Texte(
                              reperes.join('  ·  '),
                              style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (ouvrage.aQuiz)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconeAscenda(Icone.question, taille: 14, couleur: Couleurs.orTexte),
                                  const SizedBox(width: 3),
                                  Texte('quiz',
                                      style: t.textTheme.labelSmall?.copyWith(
                                          color: Couleurs.orTexte, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          if (!ouvrage.lectureIntegrale)
                            Tooltip(
                              message: "Ouvrage non redistribuable : ASCENDA en cite des "
                                  "extraits avec leur page.",
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconeAscenda(Icone.page, taille: 13, couleur: Couleurs.grisChaud),
                                    const SizedBox(width: 2),
                                    Texte('extraits',
                                        style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class PastillesSemaine extends StatelessWidget {
  const PastillesSemaine({super.key, required this.jours});

  final List<JourSemaine> jours;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lundi = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    final noms = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final jour = DateTime(lundi.year, lundi.month, lundi.day + i);
        final duJour = jours.where((j) =>
            j.jour.year == jour.year && j.jour.month == jour.month && j.jour.day == jour.day);
        final fait = duJour.any((j) => j.statut == 'fait');
        final prevu = duJour.isNotEmpty;
        final manque = prevu && !fait && jour.isBefore(DateTime.now()) &&
            !DateUtils.isSameDay(jour, DateTime.now());
        final aujourdhui = DateUtils.isSameDay(jour, DateTime.now());

        final (Color fond, Color trait, Widget contenu) = fait
            ? (Couleurs.sauge.withValues(alpha: 0.18), Couleurs.sauge,
                Coche(taille: 18, couleur: Couleurs.sauge))
            : manque
                ? (Couleurs.terracotta.withValues(alpha: 0.14), Couleurs.terracotta,
                    Croix(taille: 15, couleur: Couleurs.terracotta))
                : prevu
                    ? (Couleurs.or.withValues(alpha: 0.14), Couleurs.or,
                        Texte(noms[i],
                            style: t.textTheme.labelMedium
                                ?.copyWith(color: Couleurs.orTexte, fontWeight: FontWeight.w700)))
                    : (Colors.transparent, Colors.transparent,
                        Texte(noms[i],
                            style: t.textTheme.labelMedium?.copyWith(color: Couleurs.grisChaud)));

        return Expanded(
          child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: aujourdhui && !fait && !manque ? context.palette.accent : fond,
                shape: BoxShape.circle,
                border: aujourdhui
                    ? null
                    : Border.all(color: trait == Colors.transparent ? context.palette.trait : trait.withValues(alpha: 0.35)),
                boxShadow: aujourdhui
                    ? [BoxShadow(color: context.palette.accent.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
                    : null,
              ),
              child: Center(
                child: aujourdhui && !fait && !manque
                    ? Texte(noms[i],
                        style: t.textTheme.labelMedium
                            ?.copyWith(color: context.palette.surAccent, fontWeight: FontWeight.w700))
                    : contenu,
              ),
            ),
            const SizedBox(height: 6),
            Texte(
              DateFormat('d').format(jour),
              style: t.textTheme.labelSmall?.copyWith(
                color: aujourdhui ? Couleurs.orTexte : Couleurs.grisChaud,
                fontWeight: aujourdhui ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
          ),
        );
      }),
    );
  }
}
