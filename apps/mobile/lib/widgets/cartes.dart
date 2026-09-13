import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/modeles.dart';
import '../theme/couleurs.dart';
import '../theme/texte.dart';

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
        borderRadius: BorderRadius.zero,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Couleurs.nuit, Couleurs.nuitProfond],
        ),
        boxShadow: [
          BoxShadow(
            color: Couleurs.nuit.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Un filet d'or en tête : la seule touche décorative de la carte.
          Positioned(
            left: 0, right: 0, top: 0,
            child: Container(height: 3, color: Couleurs.or),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Texte(
                      'VOTRE SÉANCE DU JOUR',
                      style: t.textTheme.labelSmall?.copyWith(
                        color: Couleurs.orClair,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const Spacer(),
                    if (seance.enRetard)
                      Texte(
                        'en retard',
                        style: t.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFFE9A489),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Texte(
                  seance.ouvrage ?? 'Séance de lecture',
                  style: t.textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFF7F4EC),
                    fontSize: 23,
                    height: 1.22,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (seance.sousTitre != null) ...[
                  const SizedBox(height: 6),
                  Texte(
                    seance.sousTitre!,
                    style: t.textTheme.bodyMedium?.copyWith(color: const Color(0xFFB9C1D6)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    _Etiquette(icone: Icons.schedule_rounded, texte: dureeLisible(seance.dureeMin)),
                    if (seance.pages.isNotEmpty)
                      _Etiquette(icone: Icons.menu_book_outlined, texte: seance.pages),
                    if (seance.livrable == 'quiz')
                      const _Etiquette(icone: Icons.quiz_outlined, texte: 'suivie d\'un quiz'),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onCommencer,
                    child: const Texte('Commencer la séance'),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 15, color: Couleurs.orClair.withValues(alpha: 0.85)),
        const SizedBox(width: 6),
        Texte(
          texte,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: const Color(0xFFD5DAE6)),
        ),
      ],
    );
  }
}

/// Carte d'ouvrage dans la bibliothèque : une fiche de livre.
///
/// Le corpus n'a pas de couvertures. Plutôt qu'un rectangle gris, la carte
/// compose une petite couverture à la teinte du parcours, la même que sur la
/// vitrine et le dos des volumes de l'étagère : soixante livres se reconnaissent
/// alors d'un coup d'oeil. Pas de cadre, pas d'étiquettes encadrées : une
/// surface blanche posée sur le papier, et une ligne de repères discrète.
class CarteOuvrage extends StatelessWidget {
  const CarteOuvrage({super.key, required this.ouvrage, this.onTap});

  final Ouvrage ouvrage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final teinte = Couleurs.pole(ouvrage.axeSlug) ?? Couleurs.ardoise;
    final reperes = [
      if (ouvrage.niveau != null) niveaux[ouvrage.niveau] ?? ouvrage.niveau!,
      // Les pages restent sur la fiche : sur une carte étroite, trois repères
      // et deux marqueurs finissaient coupés par des points de suspension.
      if (ouvrage.dureeMin != null) dureeLisible(ouvrage.dureeMin!),
    ];
    return Material(
      color: t.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: const BoxDecoration(boxShadow: Couleurs.ombreDouce),
          child: Container(
            color: t.colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Couverture(titre: ouvrage.titre, teinte: teinte),
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
                                  const Icon(Icons.quiz_outlined, size: 13, color: Couleurs.orTexte),
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
                                    const Icon(Icons.format_quote_rounded, size: 13, color: Couleurs.grisChaud),
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
          ),
        ),
      ),
    );
  }
}

/// Une couverture composée : un aplat à la teinte du parcours, un dos plus
/// sombre, et l'initiale du titre en Fraunces.
class _Couverture extends StatelessWidget {
  const _Couverture({required this.titre, required this.teinte});
  final String titre;
  final Color teinte;

  @override
  Widget build(BuildContext context) {
    final lettre = titre.trim().isEmpty ? 'A' : titre.trim().characters.first.toUpperCase();
    return Container(
      width: 58,
      height: 82,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(teinte, Colors.white, 0.08)!, Color.lerp(teinte, Couleurs.nuit, 0.28)!],
        ),
        boxShadow: const [BoxShadow(color: Color(0x1F0B1435), blurRadius: 8, offset: Offset(2, 3))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Container(width: 5, color: Colors.black.withValues(alpha: 0.16)),
          ),
          Positioned(
            left: 12, right: 8, top: 10,
            child: Container(height: 1, color: Colors.white.withValues(alpha: 0.35)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Texte(
                lettre,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 26,
                    ),
              ),
            ),
          ),
          Positioned(
            left: 12, right: 8, bottom: 10,
            child: Container(height: 1, color: Colors.white.withValues(alpha: 0.35)),
          ),
        ],
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
                        Texte(noms[i],
                            style: t.textTheme.labelMedium
                                ?.copyWith(color: Couleurs.orTexte, fontWeight: FontWeight.w700)))
                    : (Colors.transparent, Colors.transparent,
                        Texte(noms[i],
                            style: t.textTheme.labelMedium?.copyWith(color: Couleurs.grisChaud)));

        return Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: fond,
                shape: BoxShape.rectangle,
                border: aujourdhui
                    ? Border.all(color: Couleurs.or, width: 1.6)
                    : Border.all(color: Couleurs.nuit.withValues(alpha: 0.07)),
              ),
              child: Center(child: contenu),
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
        );
      }),
    );
  }
}
