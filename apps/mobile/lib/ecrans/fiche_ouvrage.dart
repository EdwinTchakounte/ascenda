import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../widgets/cartes.dart';
import '../widgets/invitation.dart';
import '../widgets/telechargement.dart';
import '../widgets/derives.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// La fiche d'un ouvrage : thèse centrale, idées-force, sommaire, et le
/// « fait dialoguer avec » qui met en regard les thèses opposées.
class FicheOuvrage extends ConsumerWidget {
  const FicheOuvrage({super.key, required this.documentId});
  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fiche = ref.watch(ficheOuvrageProvider(documentId));
    final t = Theme.of(context);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Texte('Ouvrage')),
      body: fiche.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SqueletteCarte(lignes: 6),
        ),
        error: (e, _) => EtatErreur(
          erreur: e,
          reessayer: () => ref.invalidate(ficheOuvrageProvider(documentId)),
        ),
        data: (d) {
          final peda = d['pedagogie'] as Map<String, dynamic>? ?? {};
          final droits = d['droits'] as Map<String, dynamic>? ?? {};
          final contenu = d['contenu'] as Map<String, dynamic>? ?? {};
          final auteurs = (d['auteurs'] as List? ?? []).map((e) => '$e').toList();
          final idees = (peda['idees_force'] as List? ?? []);
          final dialogue = (d['dialogue_avec'] as List? ?? []);
          final lecture = droits['lecture_integrale'] == true;
          final axes = d['axes'] as List? ?? [];
          final questions = contenu['questions'] as int? ?? 0;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              _EnTete(
                titre: '${d['titre']}',
                sousTitre: d['sous_titre'] != null ? '${d['sous_titre']}' : null,
                axe: axes.isNotEmpty ? '${axes.first['label']}' : null,
                slug: axes.isNotEmpty && axes.first['slug'] != null ? '${axes.first['slug']}' : null,
                ligneAuteurs: [
                  if (auteurs.isNotEmpty) auteurs.join(', '),
                  if (d['annee'] != null) '${d['annee']}',
                  if (d['editeur'] != null && '${d['editeur']}'.isNotEmpty) '${d['editeur']}',
                ].join(' · '),
              ),
              const SizedBox(height: 14),
              // Trois repères en tuiles : ce qu'on veut savoir avant d'ouvrir un
              // livre tient en trois chiffres, lisibles d'un coup d'oeil.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Repere(
                      icone: Icons.signal_cellular_alt_rounded,
                      valeur: peda['niveau'] != null
                          ? (niveaux['${peda['niveau']}'] ?? '${peda['niveau']}')
                          : 'non évalué',
                      libelle: 'niveau',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Repere(
                      icone: Icons.schedule_rounded,
                      valeur: peda['duree_min'] != null ? dureeLisible(peda['duree_min'] as int) : '-',
                      libelle: 'de lecture',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Repere(
                      icone: Icons.menu_book_outlined,
                      valeur: d['pages'] != null ? '${d['pages']}' : '-',
                      libelle: 'pages',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              if (droits['pdf'] == true) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push(
                      '/pdf/$documentId?titre=${Uri.encodeComponent('${d['titre']}')}',
                    ),
                    icon: const Icon(Icons.auto_stories_rounded, size: 21),
                    label: Texte(
                      droits['pdf_octets'] is int && (droits['pdf_octets'] as int) > 0
                          ? 'Lire le PDF · ${tailleLisible(droits['pdf_octets'] as int)}'
                          : 'Lire le PDF',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],

              if (droits['message'] != null) BandeauDroits(message: '${droits['message']}'),

              if (peda['these_centrale'] != null) ...[
                const SizedBox(height: 22),
                _These(texte: '${peda['these_centrale']}'),
              ],

              if (idees.isNotEmpty) ...[
                const SizedBox(height: 28),
                const TitreSection('Idées-force'),
                const SizedBox(height: 12),
                Surface(
                  padding: const EdgeInsets.fromLTRB(16, 18, 18, 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < idees.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Numero(i + 1),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Texte(
                                    _texteIdee(idees[i]),
                                    style: t.textTheme.bodyMedium?.copyWith(height: 1.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              if (dialogue.isNotEmpty) ...[
                const SizedBox(height: 28),
                const TitreSection(
                  'Fait dialoguer avec',
                  sousTitre: 'Des ouvrages du corpus qui défendent une autre position.',
                ),
                const SizedBox(height: 12),
                for (final c in dialogue) ...[
                  Surface(
                    onTap: () => context.push('/ouvrage/${c['ouvrage_id']}'),
                    padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const IconePastille(Icons.compare_arrows_rounded, taille: 40),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Texte('${c['controverse']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.labelMedium
                                      ?.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Texte('${c['ouvrage']}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.titleMedium),
                              if (c['resume'] != null) ...[
                                const SizedBox(height: 6),
                                Texte('${c['resume']}',
                                    style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.5)),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Icon(Icons.chevron_right_rounded, size: 22, color: p.attenue),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],

              // Nos textes sur l'ouvrage : ils viennent après la fiche et avant
              // les compteurs, parce qu'on lit ce qu'un livre dit avant de
              // regarder combien il compte de chapitres.
              if (d['synthese'] != null || d['resume_executif'] != null) ...[
                const SizedBox(height: 26),
                SyntheseOuvrage(
                  synthese: d['synthese'] as Map<String, dynamic>?,
                  resumeExecutif: d['resume_executif'] as Map<String, dynamic>?,
                ),
              ],

              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Stat(
                      icone: Icons.segment_rounded,
                      valeur: '${contenu['chapitres'] ?? 0}',
                      libelle: 'chapitres',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // Le compteur devient un accès : afficher « 248 questions »
                    // sans donner le moyen de les passer, c'est une vitrine
                    // fermée.
                    child: _Stat(
                      icone: Icons.quiz_outlined,
                      valeur: '${contenu['questions'] ?? 0}',
                      libelle: 'questions',
                      onTap: questions == 0
                          ? null
                          : () => context.push(
                                '/ouvrage/$documentId/quiz'
                                '?titre=${Uri.encodeComponent('${d['titre']}')}',
                              ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      icone: Icons.format_quote_rounded,
                      valeur: '${contenu['citations'] ?? 0}',
                      libelle: 'citations',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),
              const InvitationCompte(
                raison: "Cet ouvrage vous intéresse ? Avec un compte, il entre dans "
                    "votre plan de lecture, avec ses quiz et son suivi.",
              ),

              const SizedBox(height: 26),
              BlocTelechargement(
                documentId: documentId,
                titre: '${d['titre']}',
                integral: d['droits']?['hors_ligne_integral'] == true,
                pdfOctets: d['droits']?['pdf_octets'] as int?,
              ),

              const SizedBox(height: 28),
              _Sommaire(documentId: documentId, lectureIntegrale: lecture),
            ],
          );
        },
      ),
    );
  }

  String _texteIdee(dynamic idee) {
    if (idee is String) return idee;
    if (idee is Map) {
      return '${idee['idee'] ?? idee['titre'] ?? idee.values.first}';
    }
    return '$idee';
  }
}

/// L'en-tête de la fiche : la couverture composée en grand, posée sur un voile
/// de la teinte du pôle, puis le titre en Fraunces.
///
/// Le corpus n'a pas de couvertures ; la même composition que sur la carte de
/// la bibliothèque, en grand, fait que le lecteur reconnaît le livre qu'il vient
/// de toucher.
class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.titre,
    required this.ligneAuteurs,
    this.sousTitre,
    this.axe,
    this.slug,
  });

  final String titre;
  final String? sousTitre;
  final String? axe;
  final String? slug;
  final String ligneAuteurs;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final teinte = Couleurs.pole(slug) ?? Couleurs.ardoise;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
      decoration: BoxDecoration(
        borderRadius: Rayons.grand,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            teinte.withValues(alpha: p.sombre ? 0.30 : 0.20),
            teinte.withValues(alpha: p.sombre ? 0.06 : 0.03),
          ],
        ),
        border: Border.all(color: p.trait),
      ),
      child: Column(
        children: [
          _Couverture(titre: titre, teinte: teinte),
          const SizedBox(height: 24),
          if (axe != null) ...[
            Texte(
              axe!.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelSmall?.copyWith(
                color: p.accentTexte,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Texte(
            titre,
            textAlign: TextAlign.center,
            style: t.textTheme.headlineMedium?.copyWith(fontSize: 27, height: 1.18),
          ),
          if (sousTitre != null) ...[
            const SizedBox(height: 8),
            Texte(
              sousTitre!,
              textAlign: TextAlign.center,
              style: t.textTheme.titleMedium?.copyWith(color: p.attenue, fontWeight: FontWeight.w500),
            ),
          ],
          if (ligneAuteurs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Texte(
              ligneAuteurs,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: p.texte),
            ),
          ],
        ],
      ),
    );
  }
}

/// Une couverture composée, en grand : aplat à la teinte du parcours, dos plus
/// sombre, reflet de lumière et initiale du titre en Fraunces.
///
/// Recomposée ici plutôt que partagée avec `cartes.dart` : celle de la carte est
/// dessinée pour 58 px, et ses proportions (filets, dos, initiale) ne tiennent
/// pas à cette taille.
class _Couverture extends StatelessWidget {
  const _Couverture({required this.titre, required this.teinte});
  final String titre;
  final Color teinte;

  static const _largeur = 124.0;
  static const _hauteur = 176.0;

  @override
  Widget build(BuildContext context) {
    final lettre = titre.trim().isEmpty ? 'A' : titre.trim().characters.first.toUpperCase();
    final blanc = Colors.white;
    return Container(
      width: _largeur,
      height: _hauteur,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(6), right: Radius.circular(16)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(teinte, blanc, 0.10)!, Color.lerp(teinte, Colors.black, 0.32)!],
        ),
        boxShadow: [
          BoxShadow(color: teinte.withValues(alpha: 0.38), blurRadius: 30, offset: const Offset(0, 16)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(2, 3)),
        ],
      ),
      child: Stack(
        children: [
          // Le reflet en haut à gauche : la lumière sur un livre relié.
          Positioned(
            left: -30,
            top: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [blanc.withValues(alpha: 0.22), blanc.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          // Le dos, puis la pliure juste à côté.
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Container(width: 10, color: Colors.black.withValues(alpha: 0.18)),
          ),
          Positioned(
            left: 10, top: 0, bottom: 0,
            child: Container(width: 1.2, color: blanc.withValues(alpha: 0.18)),
          ),
          Positioned(
            left: 24, right: 14, top: 18,
            child: Container(height: 1, color: blanc.withValues(alpha: 0.4)),
          ),
          Positioned(
            left: 24, right: 14, top: 23,
            child: Container(height: 1, color: blanc.withValues(alpha: 0.2)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Texte(
                lettre,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: blanc.withValues(alpha: 0.94),
                      fontSize: 54,
                      height: 1,
                    ),
              ),
            ),
          ),
          Positioned(
            left: 24, right: 14, bottom: 23,
            child: Container(height: 1, color: blanc.withValues(alpha: 0.2)),
          ),
          Positioned(
            left: 24, right: 14, bottom: 18,
            child: Container(height: 1, color: blanc.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}

/// Un repère de l'en-tête : icône, valeur, libellé.
class _Repere extends StatelessWidget {
  const _Repere({required this.icone, required this.valeur, required this.libelle});
  final IconData icone;
  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
      child: Column(
        children: [
          IconePastille(icone, taille: 32),
          const SizedBox(height: 10),
          // « Intermédiaire » dans une tuile de 88 px : la valeur se réduit
          // plutôt que de se couper.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Texte(valeur, maxLines: 1, style: t.textTheme.titleMedium?.copyWith(fontSize: 14.5)),
          ),
          const SizedBox(height: 1),
          Texte(libelle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelSmall?.copyWith(color: p.attenue)),
        ],
      ),
    );
  }
}

/// La thèse centrale, présentée comme un extrait.
class _These extends StatelessWidget {
  const _These({required this.texte});
  final String texte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Un grand guillemet en filigrane : le signe d'une citation, sans
          // prendre la place du texte.
          Positioned(
            right: 10,
            top: -6,
            child: Icon(Icons.format_quote_rounded, size: 86, color: p.accentTexte.withValues(alpha: 0.10)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconePastille(Icons.format_quote_rounded, couleur: p.accentTexte, taille: 30),
                    const SizedBox(width: 10),
                    const Expanded(child: Surtitre('Thèse centrale')),
                  ],
                ),
                const SizedBox(height: 14),
                // En Fraunces : la thèse d'un livre se lit comme un extrait, pas
                // comme une notice.
                Texte(texte,
                    style: t.textTheme.titleLarge?.copyWith(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w400,
                      height: 1.55,
                      color: p.encre,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un numéro d'ordre dans une puce dorée arrondie.
class _Numero extends StatelessWidget {
  const _Numero(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: p.accentVoile, borderRadius: Rayons.petit),
      alignment: Alignment.center,
      child: Texte('$n',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: Theme.of(context).textTheme.headlineSmall?.fontFamily,
                color: p.accentTexte,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icone, required this.valeur, required this.libelle, this.onTap});
  final IconData icone;
  final String valeur;
  final String libelle;

  /// Le compteur qu'on peut ouvrir porte une flèche et l'or : sans ce signe,
  /// rien ne le distingue de deux compteurs qu'on ne peut pas ouvrir.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final cliquable = onTap != null;
    return Surface(
      onTap: onTap,
      couleur: cliquable ? Color.alphaBlend(p.accentVoile, p.surface) : null,
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconePastille(icone, taille: 30, couleur: cliquable ? p.accentTexte : p.attenue),
              const Spacer(),
              if (cliquable) Icon(Icons.arrow_forward_rounded, size: 17, color: p.accentTexte),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Texte(valeur, maxLines: 1, style: t.textTheme.headlineSmall?.copyWith(fontSize: 24, height: 1)),
          ),
          const SizedBox(height: 4),
          Texte(
            libelle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall?.copyWith(
              color: cliquable ? p.accentTexte : p.attenue,
              fontWeight: cliquable ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sommaire extends ConsumerWidget {
  const _Sommaire({required this.documentId, required this.lectureIntegrale});
  final String documentId;
  final bool lectureIntegrale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sommaire = ref.watch(sommaireProvider(documentId));
    final t = Theme.of(context);
    final p = context.palette;

    return sommaire.when(
      loading: () => const SqueletteCarte(lignes: 4),
      error: (_, _) => const SizedBox.shrink(),
      data: (chapitres) {
        // Les chapitres d'appareil, marqués sans questions lors de la campagne
        // de génération, ne méritent pas une ligne dans le sommaire de lecture.
        final utiles = chapitres.where((c) => (c['tokens'] as int? ?? 0) >= 300).toList();
        if (utiles.isEmpty) return const SizedBox.shrink();
        final montres = utiles.take(40).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TitreSection('Sommaire'),
            const SizedBox(height: 12),
            // Une seule surface, des lignes numérotées séparées d'un filet : un
            // sommaire se parcourt d'un trait, pas carte après carte.
            Surface(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < montres.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 64, endIndent: 16, color: p.trait),
                    InkWell(
                      onTap: () => context.push('/lecture/$documentId/${montres[i]['id']}'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Texte(
                                (i + 1).toString().padLeft(2, '0'),
                                style: t.textTheme.titleMedium?.copyWith(
                                  fontFamily: t.textTheme.headlineSmall?.fontFamily,
                                  color: p.accentTexte,
                                  fontSize: 16,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Texte(
                                    '${montres[i]['titre'] ?? 'Chapitre ${montres[i]['ordre']}'}',
                                    style: t.textTheme.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Texte(
                                    [
                                      if (montres[i]['page_debut'] != null) 'p. ${montres[i]['page_debut']}',
                                      if (montres[i]['duree_min'] != null)
                                        dureeLisible(montres[i]['duree_min'] as int),
                                      if ((montres[i]['nb_questions'] as int? ?? 0) > 0)
                                        '${montres[i]['nb_questions']} questions',
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right_rounded, size: 21, color: p.attenue),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// « 2,7 Mo », « 92 Mo », « 540 Ko » : ce qu'un forfait mobile va payer.
String tailleLisible(int octets) {
  if (octets < 1000000) return '${(octets / 1000).round()} Ko';
  final mo = octets / 1000000;
  return mo < 10 ? '${mo.toStringAsFixed(1).replaceAll('.', ',')} Mo' : '${mo.round()} Mo';
}
