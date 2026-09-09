import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/modeles.dart';
import '../theme/couleurs.dart';

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

/// La carte de séance du jour : l'objet principal de l'écran d'accueil.
/// La couverture n'existe pas dans le corpus, on compose donc un fond à partir
/// du titre plutôt que d'afficher un rectangle gris.
class CarteSeance extends StatelessWidget {
  const CarteSeance({super.key, required this.seance, this.onCommencer});

  final Seance seance;
  final VoidCallback? onCommencer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Couleurs.nuit, Couleurs.nuitProfond],
        ),
        boxShadow: [
          BoxShadow(
            color: Couleurs.nuit.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -60,
            top: -50,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Couleurs.or.withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'VOTRE SÉANCE',
                      style: t.textTheme.labelSmall?.copyWith(
                        color: Couleurs.orClair,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const Spacer(),
                    if (seance.enRetard)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Couleurs.terracotta.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'en retard',
                          style: t.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFFE9A489),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  seance.ouvrage ?? 'Séance de lecture',
                  style: t.textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFF4F1E8),
                    fontSize: 21,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (seance.sousTitre != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    seance.sousTitre!,
                    style: t.textTheme.bodyMedium?.copyWith(color: const Color(0xFFB9C1D6)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Etiquette(icone: Icons.schedule_rounded, texte: dureeLisible(seance.dureeMin)),
                    if (seance.pages.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _Etiquette(icone: Icons.menu_book_outlined, texte: seance.pages),
                    ],
                    if (seance.livrable == 'quiz') ...[
                      const SizedBox(width: 8),
                      const _Etiquette(icone: Icons.quiz_outlined, texte: 'quiz'),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onCommencer,
                    child: const Text('Commencer la séance'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Etiquette extends StatelessWidget {
  const _Etiquette({required this.icone, required this.texte});
  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 13, color: const Color(0xFFB9C1D6)),
          const SizedBox(width: 5),
          Text(
            texte,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: const Color(0xFFB9C1D6)),
          ),
        ],
      ),
    );
  }
}

/// Carte d'ouvrage dans la bibliothèque.
class CarteOuvrage extends StatelessWidget {
  const CarteOuvrage({super.key, required this.ouvrage, this.onTap});

  final Ouvrage ouvrage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    ouvrage.titre,
                    style: t.textTheme.titleMedium?.copyWith(fontSize: 15.5, height: 1.3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!ouvrage.lectureIntegrale)
                  Tooltip(
                    message: "Ouvrage non redistribuable : ASCENDA en cite des "
                        "extraits avec leur page.",
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: t.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('extraits', style: t.textTheme.labelSmall),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ouvrage.auteursCourt + (ouvrage.annee != null ? ' · ${ouvrage.annee}' : ''),
              style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (ouvrage.these != null) ...[
              const SizedBox(height: 10),
              Text(
                ouvrage.these!,
                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud, height: 1.55),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (ouvrage.niveau != null)
                  _Pilule(texte: niveaux[ouvrage.niveau] ?? ouvrage.niveau!),
                if (ouvrage.dureeMin != null) _Pilule(texte: dureeLisible(ouvrage.dureeMin!)),
                if (ouvrage.pages != null) _Pilule(texte: '${ouvrage.pages} p.'),
                if (ouvrage.aQuiz) const _Pilule(texte: 'quiz', accent: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pilule extends StatelessWidget {
  const _Pilule({required this.texte, this.accent = false});
  final String texte;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent
            ? Couleurs.or.withValues(alpha: 0.13)
            : t.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texte,
        style: t.textTheme.labelSmall?.copyWith(
          color: accent ? Couleurs.orTexte : Couleurs.grisChaud,
          fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// Les sept jours de la semaine en pastilles.
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
                const Icon(Icons.check_rounded, size: 17, color: Couleurs.sauge))
            : manque
                ? (Couleurs.terracotta.withValues(alpha: 0.14), Couleurs.terracotta,
                    Icon(Icons.remove_rounded, size: 17, color: Couleurs.terracotta))
                : prevu
                    ? (Couleurs.or.withValues(alpha: 0.14), Couleurs.or,
                        Text(noms[i],
                            style: t.textTheme.labelMedium
                                ?.copyWith(color: Couleurs.orTexte, fontWeight: FontWeight.w700)))
                    : (t.colorScheme.surfaceContainer, Colors.transparent,
                        Text(noms[i],
                            style: t.textTheme.labelMedium?.copyWith(color: Couleurs.grisChaud)));

        return Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: fond,
                shape: BoxShape.circle,
                border: aujourdhui ? Border.all(color: Couleurs.or, width: 2) : null,
              ),
              child: Center(child: contenu),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('d').format(jour),
              style: t.textTheme.labelSmall?.copyWith(
                color: aujourdhui ? Couleurs.orTexte : Couleurs.grisChaud,
                fontWeight: aujourdhui ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        );
      }),
    );
  }
}
