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

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if ((d['axes'] as List? ?? []).isNotEmpty) ...[
                Texte(
                  '${(d['axes'] as List).first['label']}'.toUpperCase(),
                  style: t.textTheme.labelSmall?.copyWith(
                    color: Couleurs.orTexte, fontWeight: FontWeight.w700, letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Texte('${d['titre']}', style: t.textTheme.headlineMedium?.copyWith(fontSize: 28, height: 1.18)),
              if (d['sous_titre'] != null) ...[
                const SizedBox(height: 6),
                Texte('${d['sous_titre']}',
                    style: t.textTheme.titleMedium?.copyWith(color: Couleurs.grisChaud, fontWeight: FontWeight.w500)),
              ],
              const SizedBox(height: 10),
              Texte(
                [
                  if (auteurs.isNotEmpty) auteurs.join(', '),
                  if (d['annee'] != null) '${d['annee']}',
                  if (d['editeur'] != null && '${d['editeur']}'.isNotEmpty) '${d['editeur']}',
                ].join(' · '),
                style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
              ),
              const SizedBox(height: 20),
              // Trois repères, sans cadres : ce qu'on veut savoir avant d'ouvrir
              // un livre tient en trois chiffres.
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: Couleurs.nuit.withValues(alpha: 0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    _Repere(
                      icone: Icons.signal_cellular_alt_rounded,
                      valeur: peda['niveau'] != null
                          ? (niveaux['${peda['niveau']}'] ?? '${peda['niveau']}')
                          : 'non évalué',
                      libelle: 'niveau',
                    ),
                    _Repere(
                      icone: Icons.schedule_rounded,
                      valeur: peda['duree_min'] != null ? dureeLisible(peda['duree_min'] as int) : '-',
                      libelle: 'de lecture',
                    ),
                    _Repere(
                      icone: Icons.menu_book_outlined,
                      valeur: d['pages'] != null ? '${d['pages']}' : '-',
                      libelle: 'pages',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (droits['pdf'] == true) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: () => context.push(
                      '/pdf/$documentId?titre=${Uri.encodeComponent('${d['titre']}')}',
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                    label: Texte(droits['pdf_octets'] is int && (droits['pdf_octets'] as int) > 0
                        ? 'Lire le PDF · ${tailleLisible(droits['pdf_octets'] as int)}'
                        : 'Lire le PDF'),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              if (droits['message'] != null) ...[
                const SizedBox(height: 8),
                BandeauDroits(message: '${droits['message']}'),
              ],

              if (peda['these_centrale'] != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  decoration: BoxDecoration(
                    color: t.colorScheme.surface,
                    boxShadow: Couleurs.ombreDouce,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.format_quote_rounded, size: 22, color: Couleurs.or),
                          const SizedBox(width: 6),
                          Texte('THÈSE CENTRALE',
                              style: t.textTheme.labelSmall?.copyWith(
                                  color: Couleurs.orTexte,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.3)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // En Fraunces : la thèse d'un livre se lit comme un
                      // extrait, pas comme une notice.
                      Texte('${peda['these_centrale']}',
                          style: t.textTheme.titleLarge?.copyWith(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w400,
                            height: 1.55,
                            color: t.colorScheme.onSurface,
                          )),
                    ],
                  ),
                ),
              ],

              if (idees.isNotEmpty) ...[
                const SizedBox(height: 26),
                Texte('Idées-force', style: t.textTheme.titleLarge),
                const SizedBox(height: 12),
                for (var i = 0; i < idees.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            color: Couleurs.or.withValues(alpha: 0.13),
                            shape: BoxShape.rectangle,
                          ),
                          child: Center(
                            child: Texte('${i + 1}',
                                style: t.textTheme.labelSmall
                                    ?.copyWith(color: Couleurs.orTexte, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Texte(
                            _texteIdee(idees[i]),
                            style: t.textTheme.bodyMedium?.copyWith(height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],

              if (dialogue.isNotEmpty) ...[
                const SizedBox(height: 20),
                Texte('Fait dialoguer avec', style: t.textTheme.titleLarge),
                const SizedBox(height: 6),
                Texte(
                  'Des ouvrages du corpus qui défendent une autre position.',
                  style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                ),
                const SizedBox(height: 12),
                for (final c in dialogue)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => context.push('/ouvrage/${c['ouvrage_id']}'),
                      borderRadius: BorderRadius.zero,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: t.colorScheme.surface,
                          borderRadius: BorderRadius.zero,
                          border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Texte('${c['controverse']}',
                                style: t.textTheme.labelMedium
                                    ?.copyWith(color: Couleurs.orTexte)),
                            const SizedBox(height: 6),
                            Texte('${c['ouvrage']}', style: t.textTheme.titleMedium),
                            if (c['resume'] != null) ...[
                              const SizedBox(height: 6),
                              Texte('${c['resume']}',
                                  style: t.textTheme.bodySmall
                                      ?.copyWith(color: Couleurs.grisChaud, height: 1.5)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
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

              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      valeur: '${contenu['chapitres'] ?? 0}',
                      libelle: 'chapitres',
                    ),
                  ),
                  Expanded(
                    // Le compteur devient un accès : afficher « 248 questions »
                    // sans donner le moyen de les passer, c'est une vitrine
                    // fermée.
                    child: InkWell(
                      borderRadius: BorderRadius.zero,
                      onTap: (contenu['questions'] as int? ?? 0) == 0
                          ? null
                          : () => context.push(
                                '/ouvrage/$documentId/quiz'
                                '?titre=${Uri.encodeComponent('${d['titre']}')}',
                              ),
                      child: _Stat(
                        valeur: '${contenu['questions'] ?? 0}',
                        libelle: 'questions',
                        cliquable: (contenu['questions'] as int? ?? 0) > 0,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
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
              BlocTelechargement(documentId: documentId, titre: '${d['titre']}'),

              const SizedBox(height: 26),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.valeur, required this.libelle, this.cliquable = false});
  final String valeur;
  final String libelle;

  /// Souligne discrètement le libellé : sans ce signe, rien ne distingue un
  /// compteur qu'on peut ouvrir de deux compteurs qu'on ne peut pas.
  final bool cliquable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        Texte(valeur, style: t.textTheme.headlineSmall?.copyWith(color: Couleurs.orTexte)),
        const SizedBox(height: 2),
        Texte(
          libelle,
          style: t.textTheme.bodySmall?.copyWith(
            color: cliquable ? Couleurs.orTexte : Couleurs.grisChaud,
            decoration: cliquable ? TextDecoration.underline : null,
            decorationColor: Couleurs.or,
          ),
        ),
      ],
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

    return sommaire.when(
      loading: () => const SqueletteCarte(lignes: 4),
      error: (_, _) => const SizedBox.shrink(),
      data: (chapitres) {
        // Les chapitres d'appareil, marqués sans questions lors de la campagne
        // de génération, ne méritent pas une ligne dans le sommaire de lecture.
        final utiles = chapitres.where((c) => (c['tokens'] as int? ?? 0) >= 300).toList();
        if (utiles.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Texte('Sommaire', style: t.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final c in utiles.take(40))
              InkWell(
                onTap: () => context.push('/lecture/$documentId/${c['id']}'),
                borderRadius: BorderRadius.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Texte(
                              '${c['titre'] ?? 'Chapitre ${c['ordre']}'}',
                              style: t.textTheme.bodyLarge,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Texte(
                              [
                                if (c['page_debut'] != null) 'p. ${c['page_debut']}',
                                if (c['duree_min'] != null)
                                  dureeLisible(c['duree_min'] as int),
                                if ((c['nb_questions'] as int? ?? 0) > 0)
                                  '${c['nb_questions']} questions',
                              ].join(' · '),
                              style: t.textTheme.bodySmall
                                  ?.copyWith(color: Couleurs.grisChaud),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 20, color: Couleurs.grisChaud),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}


class _Repere extends StatelessWidget {
  const _Repere({required this.icone, required this.valeur, required this.libelle});
  final IconData icone;
  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icone, size: 18, color: Couleurs.orTexte),
          const SizedBox(height: 6),
          Texte(valeur, style: t.textTheme.titleMedium?.copyWith(fontSize: 14.5), textAlign: TextAlign.center),
          Texte(libelle, style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
        ],
      ),
    );
  }
}

/// « 2,7 Mo », « 92 Mo », « 540 Ko » : ce qu'un forfait mobile va payer.
String tailleLisible(int octets) {
  if (octets < 1000000) return '${(octets / 1000).round()} Ko';
  final mo = octets / 1000000;
  return mo < 10 ? '${mo.toStringAsFixed(1).replaceAll('.', ',')} Mo' : '${mo.round()} Mo';
}
