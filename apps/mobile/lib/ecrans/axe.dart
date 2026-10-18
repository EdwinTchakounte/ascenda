import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/papier.dart';
import '../widgets/etats.dart';
import '../widgets/invitation.dart';
import '../widgets/livre.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

class EcranAxe extends ConsumerWidget {
  const EcranAxe({super.key, required this.slug});

  final String slug;
  static const _rang = {'debutant': 0, 'intermediaire': 1, 'avance': 2};
  static const _niveaux = {
    'debutant': 'Débutant',
    'intermediaire': 'Intermédiaire',
    'avance': 'Avancé',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final axe = ref.watch(axeProvider(slug));

    return Scaffold(
      appBar: AppBar(title: const Texte('Axe de lecture')),
      body: FondPapier(
        child: SafeArea(
          bottom: false,
          child: axe.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: SqueletteCarte(lignes: 5),
            ),
            error: (e, _) => EtatErreur(
              erreur: e,
              reessayer: () => ref.invalidate(axeProvider(slug)),
            ),
            data: (d) {
              final ouvrages = ((d['ouvrages'] as List?) ?? [])
                  .cast<Map<String, dynamic>>()
                  .toList()
                ..sort((a, b) {
                  final ra = _rang['${a['niveau']}'] ?? 1;
                  final rb = _rang['${b['niveau']}'] ?? 1;
                  if (ra != rb) return ra.compareTo(rb);
                  return (a['pages'] as int? ?? 0).compareTo(b['pages'] as int? ?? 0);
                });
              int part(Map<String, dynamic> o, String cle, String cleLivre) =>
                  (o['perimetre'] as Map?)?[cle] as int? ?? o[cleLivre] as int? ?? 0;
              final pages = ouvrages.fold<int>(0, (s, o) => s + part(o, 'pages', 'pages'));
              final minutes = ouvrages.fold<int>(0, (s, o) => s + part(o, 'duree_min', 'duree_min'));
              final pole = Couleurs.pole(slug);
              final teinte = pole ?? p.accentTexte;
              final heures = (minutes / 60).round();

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                    decoration: BoxDecoration(
                      borderRadius: Rayons.grand,
                      border: Border.all(color: p.trait),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          teinte.withValues(alpha: p.sombre ? 0.30 : 0.18),
                          teinte.withValues(alpha: p.sombre ? 0.06 : 0.03),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (pole != null)
                              Container(
                                width: 46,
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: pole,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                        color: pole.withValues(alpha: 0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6)),
                                  ],
                                ),
                                child: const IconeAscenda(Icone.boussole, taille: 25, couleur: Colors.white),
                              )
                            else
                              Container(
                                width: 46,
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: p.accentVoile,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: p.accentTexte.withValues(alpha: 0.32)),
                                ),
                                child: IconeAscenda(Icone.boussole, taille: 25, couleur: p.accentTexte),
                              ),
                            const SizedBox(width: 14),
                            const Expanded(child: EtiquetteCrochet('axe de lecture')),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Texte('${d['label']}', style: t.textTheme.headlineMedium?.copyWith(fontSize: 27)),
                        if ('${d['description'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Filet(redouble: true),
                          const SizedBox(height: 12),
                          Texte('${d['description']}',
                              style: t.textTheme.bodyMedium?.copyWith(height: 1.65, color: p.texte)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Mesure(
                          icone: Icone.volumes,
                          valeur: ouvrages.length,
                          libelle: ouvrages.length > 1 ? 'ouvrages' : 'ouvrage',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Mesure(icone: Icone.page, valeur: pages, libelle: 'pages'),
                      ),
                      if (minutes > 0) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Mesure(
                            icone: Icone.soleil,
                            valeur: heures,
                            unite: 'h',
                            libelle: 'de lecture',
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  const InvitationCompte(
                    compact: true,
                    raison: "Créez votre compte et ASCENDA découpe cet axe en séances "
                        "datées, à la mesure du temps dont vous disposez.",
                  ),
                  const TitreSection(
                    'Dans quel ordre',
                    sousTitre: "Du plus accessible au plus exigeant. C'est l'ordre que suit le "
                        "chronogramme, et il compte autant que la liste elle-même.",
                  ),
                  const SizedBox(height: 14),
                  for (var i = 0; i < ouvrages.length; i++) ...[
                    Apparition(
                      rang: i,
                      child: _LigneOuvrage(
                        rang: i + 1,
                        ouvrage: ouvrages[i],
                        niveau: _niveaux['${ouvrages[i]['niveau']}'],
                        teinte: teinte,
                        slug: slug,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 14),
                  Surface(
                    onTap: () => context.push('/notions?axe=$slug'),
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.accentVoile,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: p.accentTexte.withValues(alpha: 0.3)),
                          ),
                          child: IconeAscenda(Icone.clef, taille: 21, couleur: p.accentTexte),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Texte('Les notions de cet axe',
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                        ),
                        IconeAscenda(Icone.fleche, taille: 19, couleur: p.attenue),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Fleuron(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Mesure extends StatelessWidget {
  const _Mesure({required this.icone, required this.valeur, required this.libelle, this.unite});

  final Icone icone;
  final int valeur;
  final String? unite;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final chiffre = t.textTheme.headlineSmall?.copyWith(fontSize: 24, height: 1);
    return Surface(
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconeAscenda(icone, taille: 20, couleur: p.accentTexte),
          const SizedBox(height: 10),
          const Filet(),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                CompteurAnime(valeur, style: chiffre, suffixe: unite == null ? '' : ' $unite'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Texte(libelle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
        ],
      ),
    );
  }
}

class _LigneOuvrage extends StatelessWidget {
  const _LigneOuvrage({
    required this.rang,
    required this.ouvrage,
    required this.teinte,
    this.niveau,
    this.slug,
  });

  final int rang;
  final Map<String, dynamic> ouvrage;
  final String? niveau;
  final Color teinte;
  final String? slug;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final o = ouvrage;
    final auteurs = ((o['auteurs'] as List?) ?? []).join(', ');
    final perimetre = o['perimetre'] as Map<String, dynamic>?;
    final sections = ((perimetre?['sections'] as List?) ?? []).cast<Map<String, dynamic>>();
    final details = [
      ?niveau,
      if (perimetre != null)
        '${millier(perimetre['pages'] as num)} pages lues sur ${millier(o['pages'] as num)}'
      else if (o['pages'] != null)
        '${millier(o['pages'] as num)} pages',
      if (o['lecture_integrale'] == false) 'extraits',
    ].join('  ·  ');

    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push('/ouvrage/${o['id']}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Texte('$rang',
                          textAlign: TextAlign.center,
                          style: t.textTheme.titleLarge?.copyWith(
                            fontSize: 15,
                            color: teinte,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DosLivre(titre: '${o['titre']}', axeSlug: slug, hauteur: 82, largeur: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Texte('${o['titre']}',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                        const SizedBox(height: 3),
                        Texte(
                          [if (auteurs.isNotEmpty) auteurs, details].where((s) => s.isNotEmpty).join('\n'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: IconeAscenda(Icone.fleche, taille: 19, couleur: p.attenue),
                  ),
                ],
              ),
            ),
          ),
          if (sections.isNotEmpty) ...[
            const Filet(),
            Container(
              color: p.surfaceCreuse.withValues(alpha: 0.45),
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(66, 0, 16, 8),
                    child: EtiquetteCrochet('Ce que ce parcours en lit', capitales: false),
                  ),
                  for (final sec in sections)
                    InkWell(
                      onTap: () => context.push(
                        '/lecture/${o['id']}/${sec['chapitre_id']}'
                        '?page_debut=${sec['page_debut']}&page_fin=${sec['page_fin']}',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(66, 8, 16, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Texte('${sec['titre']}', style: t.textTheme.bodyMedium),
                            ),
                            const SizedBox(width: 10),
                            Pastille(
                              (sec['sous_sections'] as int? ?? 0) > 0
                                  ? '${sec['sous_sections']} section${sec['sous_sections'] == 1 ? '' : 's'}'
                                  : 'p. ${sec['page_debut']}',
                              couleur: p.attenue,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
