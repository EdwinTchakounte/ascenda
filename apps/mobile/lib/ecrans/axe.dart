import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';
import '../widgets/invitation.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// La fiche d'un axe : ce qu'il contient, dans l'ordre où il le contient.
///
/// Un axe n'est pas un rayon de bibliothèque. Il ordonne : celui-ci d'abord
/// parce qu'il pose le vocabulaire, celui-là ensuite parce qu'il le discute.
/// L'écran montre donc les ouvrages du plus accessible au plus exigeant, et
/// non par ordre alphabétique.
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
      body: SafeArea(
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
            // Un ouvrage borné (le Mémento de l'agronome dans « Protection des
            // cultures ») compte pour la part que l'axe en lit, pas pour ses 1 698 pages.
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
                // L'en-tête sur un voile de la teinte du pôle : l'axe se
                // reconnaît à la couleur de ses livres dans la bibliothèque.
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
                      if (pole != null)
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: pole,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: pole.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
                            ],
                          ),
                          // Texte et icône blancs sur une teinte de pôle, fixe
                          // dans les quatre thèmes.
                          child: const Icon(Icons.route_rounded, size: 26, color: Colors.white),
                        )
                      else
                        const IconePastille(Icons.route_rounded, taille: 50),
                      const SizedBox(height: 18),
                      Texte('${d['label']}', style: t.textTheme.headlineMedium?.copyWith(fontSize: 27)),
                      if ('${d['description'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 10),
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
                        icone: Icons.auto_stories_outlined,
                        valeur: '${ouvrages.length}',
                        libelle: ouvrages.length > 1 ? 'ouvrages' : 'ouvrage',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Mesure(icone: Icons.menu_book_outlined, valeur: '$pages', libelle: 'pages'),
                    ),
                    if (minutes > 0) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Mesure(
                          icone: Icons.schedule_rounded,
                          valeur: '$heures',
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
                  _LigneOuvrage(
                    rang: i + 1,
                    ouvrage: ouvrages[i],
                    niveau: _niveaux['${ouvrages[i]['niveau']}'],
                    teinte: teinte,
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 14),
                Surface(
                  onTap: () => context.push('/notions?axe=$slug'),
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Row(
                    children: [
                      const IconePastille(Icons.local_offer_outlined, taille: 42),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Texte('Les notions de cet axe',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                      ),
                      Icon(Icons.chevron_right_rounded, color: p.attenue),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Mesure extends StatelessWidget {
  const _Mesure({required this.icone, required this.valeur, required this.libelle, this.unite});
  final IconData icone;
  final String valeur;
  final String? unite;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconePastille(icone, taille: 30),
          const SizedBox(height: 12),
          // Le chiffre en grand, son unité en petit : « 1 240 pages » se lit
          // d'abord comme une quantité.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: valeur),
                if (unite != null)
                  TextSpan(text: ' $unite', style: t.textTheme.labelLarge?.copyWith(color: p.attenue)),
              ]),
              maxLines: 1,
              style: t.textTheme.headlineSmall?.copyWith(fontSize: 24, height: 1),
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
  const _LigneOuvrage({required this.rang, required this.ouvrage, required this.teinte, this.niveau});

  final int rang;
  final Map<String, dynamic> ouvrage;
  final String? niveau;
  final Color teinte;

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
        '${perimetre['pages']} pages lues sur ${o['pages']}'
      else if (o['pages'] != null)
        '${o['pages']} pages',
      if (o['lecture_integrale'] == false) 'extraits',
    ].join('  ·  ');

    // Une seule surface par ouvrage ; la tête ouvre la fiche, chaque section
    // ouvre sa lecture. La surface elle-même ne réagit pas, pour qu'un toucher
    // entre deux sections ne mène pas à la fiche par surprise.
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
                children: [
                  // Le rang, sur la teinte du pôle : c'est l'ordre de lecture,
                  // l'information que l'écran existe pour donner.
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: teinte.withValues(alpha: p.sombre ? 0.24 : 0.13),
                      borderRadius: Rayons.moyen,
                    ),
                    alignment: Alignment.center,
                    child: Texte('$rang',
                        style: t.textTheme.titleLarge?.copyWith(
                          fontSize: 17,
                          color: p.encre,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                  ),
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
                  Icon(Icons.chevron_right_rounded, size: 22, color: p.attenue),
                ],
              ),
            ),
          ),
          if (sections.isNotEmpty) ...[
            Divider(height: 1, color: p.trait),
            Container(
              color: p.surfaceCreuse.withValues(alpha: 0.45),
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(66, 0, 16, 6),
                    child: Texte('Ce que ce parcours en lit',
                        style: t.textTheme.labelLarge?.copyWith(color: p.accentTexte)),
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
