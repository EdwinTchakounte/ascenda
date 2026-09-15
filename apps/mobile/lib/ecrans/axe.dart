import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';
import '../widgets/invitation.dart';
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

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Texte('${d['label']}', style: t.textTheme.headlineSmall),
                if ('${d['description'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Texte('${d['description']}',
                      style: t.textTheme.bodyMedium
                          ?.copyWith(height: 1.65, color: Couleurs.grisChaud)),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 26,
                  runSpacing: 12,
                  children: [
                    _Mesure(valeur: '${ouvrages.length}', libelle: 'ouvrages'),
                    _Mesure(valeur: '$pages', libelle: 'pages'),
                    if (minutes > 0)
                      _Mesure(valeur: '${(minutes / 60).round()} h', libelle: 'de lecture'),
                  ],
                ),
                const SizedBox(height: 24),
                const InvitationCompte(
                  compact: true,
                  raison: "Créez votre compte et ASCENDA découpe cet axe en séances "
                      "datées, à la mesure du temps dont vous disposez.",
                ),
                Texte('Dans quel ordre', style: t.textTheme.titleLarge),
                const SizedBox(height: 4),
                Texte(
                  "Du plus accessible au plus exigeant. C'est l'ordre que suit le "
                  "chronogramme, et il compte autant que la liste elle-même.",
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: Couleurs.grisChaud, height: 1.5),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < ouvrages.length; i++)
                  _LigneOuvrage(
                    rang: i + 1,
                    ouvrage: ouvrages[i],
                    niveau: _niveaux['${ouvrages[i]['niveau']}'],
                  ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: () => context.push('/notions?axe=$slug'),
                  icon: const Icon(Icons.local_offer_outlined, size: 18),
                  label: const Texte('Les notions de cet axe'),
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
  const _Mesure({required this.valeur, required this.libelle});
  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Texte(valeur,
            style: t.textTheme.headlineSmall?.copyWith(color: Couleurs.orTexte)),
        Texte(libelle,
            style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
      ],
    );
  }
}

class _LigneOuvrage extends StatelessWidget {
  const _LigneOuvrage({required this.rang, required this.ouvrage, this.niveau});

  final int rang;
  final Map<String, dynamic> ouvrage;
  final String? niveau;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
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

    final ligne = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox(
          width: 26,
          child: Texte('$rang',
              textAlign: TextAlign.center,
              style: t.textTheme.titleMedium?.copyWith(
                color: Couleurs.grisChaud,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
        title: Texte('${o['titre']}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium),
        subtitle: Texte(
          [if (auteurs.isNotEmpty) auteurs, details].where((s) => s.isNotEmpty).join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud, height: 1.4),
        ),
        onTap: () => context.push('/ouvrage/${o['id']}'),
      ),
    );
    if (sections.isEmpty) return ligne;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ligne,
        Padding(
          padding: const EdgeInsets.only(left: 42, bottom: 8),
          child: Texte('Ce que ce parcours en lit',
              style: t.textTheme.labelLarge?.copyWith(color: Couleurs.orTexte)),
        ),
        for (final sec in sections)
          InkWell(
            onTap: () => context.push(
              '/lecture/${o['id']}/${sec['chapitre_id']}'
              '?page_debut=${sec['page_debut']}&page_fin=${sec['page_fin']}',
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(42, 7, 0, 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Texte('${sec['titre']}', style: t.textTheme.bodyMedium),
                  ),
                  const SizedBox(width: 10),
                  Texte(
                    (sec['sous_sections'] as int? ?? 0) > 0
                        ? '${sec['sous_sections']} section${sec['sous_sections'] == 1 ? '' : 's'}'
                        : 'p. ${sec['page_debut']}',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: Couleurs.grisChaud,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}
