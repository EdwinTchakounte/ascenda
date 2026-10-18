import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import '../widgets/cartes.dart';
import '../widgets/derives.dart';
import '../widgets/etats.dart';
import '../widgets/invitation.dart';
import '../widgets/livre.dart';
import '../widgets/telechargement.dart';
import '../widgets/ui.dart';

class FicheOuvrage extends ConsumerWidget {
  const FicheOuvrage({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fiche = ref.watch(ficheOuvrageProvider(documentId));
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Texte('Ouvrage')),
      body: FondPapier(
        child: fiche.when(
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
            final titre = '${d['titre']}';
            final slug = axes.isNotEmpty && axes.first['slug'] != null ? '${axes.first['slug']}' : null;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                _PageDeTitre(
                  titre: titre,
                  sousTitre: d['sous_titre'] != null ? '${d['sous_titre']}' : null,
                  axe: axes.isNotEmpty ? '${axes.first['label']}' : null,
                  slug: slug,
                  auteurs: auteurs,
                  colophon: [
                    if (auteurs.isNotEmpty) auteurs.join(', '),
                    if (d['annee'] != null) '${d['annee']}',
                    if (d['editeur'] != null && '${d['editeur']}'.isNotEmpty) '${d['editeur']}',
                  ].join(' · '),
                ),
                const SizedBox(height: 18),
                _Reperes(
                  niveau: peda['niveau'] != null
                      ? (niveaux['${peda['niveau']}'] ?? '${peda['niveau']}')
                      : 'non évalué',
                  duree: peda['duree_min'] != null ? dureeLisible(peda['duree_min'] as int) : '-',
                  pages: d['pages'] != null ? millier(d['pages'] as num) : '-',
                ),
                const SizedBox(height: 22),

                if (droits['pdf'] == true) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.push(
                        '/pdf/$documentId?titre=${Uri.encodeComponent(titre)}',
                      ),
                      icon: IconeAscenda(Icone.page, taille: 20, couleur: p.surAccent),
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
                  const SizedBox(height: 24),
                  _These(texte: '${peda['these_centrale']}'),
                ],

                if (idees.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const TitreSection('Idées-force'),
                  const SizedBox(height: 12),
                  Surface(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < idees.length; i++) ...[
                          if (i > 0)
                            const Padding(
                              padding: EdgeInsets.only(left: 52, right: 18),
                              child: Filet(),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Numero(i + 1),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Texte(
                                    _texteIdee(idees[i]),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(height: 1.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                    _Contrepoint(
                      controverse: '${c['controverse']}',
                      ouvrage: '${c['ouvrage']}',
                      resume: c['resume'] != null ? '${c['resume']}' : null,
                      onTap: () => context.push('/ouvrage/${c['ouvrage_id']}'),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],

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
                        icone: Icone.volumes,
                        valeur: millier(contenu['chapitres'] as num? ?? 0),
                        libelle: 'chapitres',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(
                        icone: Icone.question,
                        valeur: millier(questions),
                        libelle: 'questions',
                        onTap: questions == 0
                            ? null
                            : () => context.push(
                                  '/ouvrage/$documentId/quiz'
                                  '?titre=${Uri.encodeComponent(titre)}',
                                ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(
                        icone: Icone.encrier,
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
                  titre: titre,
                  integral: d['droits']?['hors_ligne_integral'] == true,
                  pdfOctets: d['droits']?['pdf_octets'] as int?,
                ),

                const SizedBox(height: 28),
                _Sommaire(documentId: documentId, lectureIntegrale: lecture),
              ],
            );
          },
        ),
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

class _PageDeTitre extends StatelessWidget {
  const _PageDeTitre({
    required this.titre,
    required this.colophon,
    required this.auteurs,
    this.sousTitre,
    this.axe,
    this.slug,
  });

  final String titre;
  final String? sousTitre;
  final String? axe;
  final String? slug;
  final List<String> auteurs;
  final String colophon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Column(
      children: [
        const SizedBox(height: 6),
        CouvertureLivre(
          titre: titre,
          auteurs: auteurs.isEmpty ? null : auteurs.take(2).join(', '),
          axeSlug: slug,
          hauteur: 232,
        ),
        const SizedBox(height: 26),
        if (axe != null) ...[
          EtiquetteCrochet(axe!),
          const SizedBox(height: 14),
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
        if (colophon.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Filet(redouble: true),
          const SizedBox(height: 12),
          Texte(
            colophon,
            textAlign: TextAlign.center,
            style: t.textTheme.labelMedium?.copyWith(
              color: p.texte,
              letterSpacing: 0.9,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Filet(),
        ],
      ],
    );
  }
}

class _Reperes extends StatelessWidget {
  const _Reperes({required this.niveau, required this.duree, required this.pages});

  final String niveau;
  final String duree;
  final String pages;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final filet = Container(
      width: 1,
      height: 40,
      color: p.encre.withValues(alpha: p.sombre ? 0.22 : 0.14),
    );
    return Row(
      children: [
        Expanded(child: _Repere(valeur: niveau, libelle: 'niveau')),
        filet,
        Expanded(child: _Repere(valeur: duree, libelle: 'de lecture')),
        filet,
        Expanded(child: _Repere(valeur: pages, libelle: 'pages')),
      ],
    );
  }
}

class _Repere extends StatelessWidget {
  const _Repere({required this.valeur, required this.libelle});

  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Texte(
            valeur,
            maxLines: 1,
            style: t.textTheme.headlineSmall?.copyWith(fontSize: 17, height: 1.2),
          ),
        ),
        const SizedBox(height: 6),
        Texte(
          libelle.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.textTheme.labelSmall?.copyWith(
            color: p.attenue,
            fontSize: 10.5,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _These extends StatelessWidget {
  const _These({required this.texte});

  final String texte;
  static final _lettre = RegExp(r'\p{L}', unicode: true);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final net = texte.trim();
    final style = t.textTheme.titleLarge?.copyWith(
      fontSize: 17.5,
      fontWeight: FontWeight.w400,
      height: 1.55,
      color: p.encre,
    );
    final initiale = net.isEmpty ? null : net.characters.first;
    final avecLettrine = initiale != null && _lettre.hasMatch(initiale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EtiquetteCrochet('thèse centrale'),
        const SizedBox(height: 18),
        if (avecLettrine)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Lettrine(initiale, taille: 54),
              const SizedBox(width: 14),
              Expanded(
                child: Texte(net.characters.skip(1).toString().trimLeft(), style: style),
              ),
            ],
          )
        else
          Texte(net, style: style),
        const SizedBox(height: 20),
        const Fleuron(),
      ],
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero(this.n);

  final int n;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      width: 20,
      child: Texte(
        n.toString().padLeft(2, '0'),
        style: t.textTheme.titleMedium?.copyWith(
          fontFamily: t.textTheme.headlineSmall?.fontFamily,
          color: context.palette.accentTexte,
          fontSize: 15,
          height: 1.7,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _Contrepoint extends StatelessWidget {
  const _Contrepoint({
    required this.controverse,
    required this.ouvrage,
    required this.onTap,
    this.resume,
  });

  final String controverse;
  final String ouvrage;
  final String? resume;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DosLivre(titre: ouvrage, hauteur: 84, largeur: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte(
                  controverse,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.labelMedium?.copyWith(
                    color: p.accentTexte,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Texte(ouvrage, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                if (resume != null) ...[
                  const SizedBox(height: 8),
                  const Filet(),
                  const SizedBox(height: 8),
                  Texte(
                    resume!,
                    style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 6),
            child: IconeAscenda(Icone.fleche, taille: 17, couleur: p.attenue),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icone, required this.valeur, required this.libelle, this.onTap});

  final Icone icone;
  final String valeur;
  final String libelle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final cliquable = onTap != null;
    return Surface(
      onTap: onTap,
      couleur: cliquable ? Color.alphaBlend(p.accentVoile, p.surface) : null,
      padding: const EdgeInsets.fromLTRB(12, 13, 10, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconeAscenda(icone, taille: 19, couleur: cliquable ? p.accentTexte : p.attenue),
              const Spacer(),
              if (cliquable) IconeAscenda(Icone.fleche, taille: 16, couleur: p.accentTexte),
            ],
          ),
          const SizedBox(height: 10),
          const Filet(),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Texte(
              valeur,
              maxLines: 1,
              style: t.textTheme.headlineSmall?.copyWith(fontSize: 24, height: 1),
            ),
          ),
          const SizedBox(height: 5),
          Texte(
            libelle.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.labelSmall?.copyWith(
              color: cliquable ? p.accentTexte : p.attenue,
              fontSize: 10.5,
              letterSpacing: 1.1,
              fontWeight: cliquable ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sommaire extends ConsumerStatefulWidget {
  const _Sommaire({required this.documentId, required this.lectureIntegrale});

  final String documentId;
  final bool lectureIntegrale;

  @override
  ConsumerState<_Sommaire> createState() => _SommaireState();
}

class _SommaireState extends ConsumerState<_Sommaire> {
  static const _pas = 40;
  int _montres = _pas;

  @override
  Widget build(BuildContext context) {
    final sommaire = ref.watch(sommaireProvider(widget.documentId));
    final t = Theme.of(context);
    final p = context.palette;

    return sommaire.when(
      loading: () => const SqueletteCarte(lignes: 4),
      error: (_, _) => const SizedBox.shrink(),
      data: (chapitres) {
        final utiles = chapitres.where((c) => (c['tokens'] as int? ?? 0) >= 300).toList();
        if (utiles.isEmpty) return const SizedBox.shrink();
        final fin = _montres < utiles.length ? _montres : utiles.length;
        final restants = utiles.length - fin;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TitreSection(
              'Sommaire',
              sousTitre: utiles.length == 1 ? '1 chapitre' : '${utiles.length} chapitres',
            ),
            const SizedBox(height: 12),
            Surface(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < fin; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.only(left: 52, right: 16),
                        child: Filet(),
                      ),
                    _LigneSommaire(
                      rang: i + 1,
                      titre: '${utiles[i]['titre'] ?? 'Chapitre ${utiles[i]['ordre']}'}',
                      folio: utiles[i]['page_debut'] != null ? 'p. ${utiles[i]['page_debut']}' : null,
                      detail: [
                        if (utiles[i]['duree_min'] != null) dureeLisible(utiles[i]['duree_min'] as int),
                        if ((utiles[i]['nb_questions'] as int? ?? 0) > 0)
                          '${millier(utiles[i]['nb_questions'] as num)} questions',
                      ].join(' · '),
                      onTap: () => context.push('/lecture/${widget.documentId}/${utiles[i]['id']}'),
                    ),
                  ],
                ],
              ),
            ),
            if (restants > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => setState(() => _montres += _pas),
                  child: Texte('Afficher la suite ($restants restants)'),
                ),
              ),
            ] else if (utiles.length > _pas) ...[
              const SizedBox(height: 18),
              const Fleuron(),
            ],
            if (restants > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Texte(
                  'Chapitres $fin sur ${utiles.length}.',
                  style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 0.6),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LigneSommaire extends StatelessWidget {
  const _LigneSommaire({
    required this.rang,
    required this.titre,
    required this.detail,
    required this.onTap,
    this.folio,
  });

  final int rang;
  final String titre;
  final String detail;
  final String? folio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final chiffres = t.textTheme.labelSmall?.copyWith(
      color: p.attenue,
      letterSpacing: 0.4,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Texte(
                rang.toString().padLeft(2, '0'),
                style: t.textTheme.titleMedium?.copyWith(
                  fontFamily: t.textTheme.headlineSmall?.fontFamily,
                  color: p.accentTexte,
                  fontSize: 15,
                  height: 1.45,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Texte(
                    titre,
                    style: t.textTheme.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Texte(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: chiffres),
                  ],
                ],
              ),
            ),
            if (folio != null) ...[
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Texte(folio!, maxLines: 1, style: chiffres),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String tailleLisible(int octets) {
  if (octets < 1000000) return '${(octets / 1000).round()} Ko';
  final mo = octets / 1000000;
  return mo < 10 ? '${mo.toStringAsFixed(1).replaceAll('.', ',')} Mo' : '${mo.round()} Mo';
}
