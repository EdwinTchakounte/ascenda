import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/papier.dart';
import '../widgets/etats.dart';
import '../widgets/illustrations.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// Le glossaire : les notions du corpus, et où elles sont dites.
///
/// Ce n'est pas un dictionnaire. Une notion n'a d'intérêt ici que parce qu'on
/// peut aller lire le passage qui la définit, dans l'ouvrage qui la définit.
/// Le nombre d'occurrences est donc affiché, et une notion qui n'est ancrée
/// nulle part est reléguée : elle vient d'une fiche de lecture sans que le
/// texte l'emploie, et elle ne mène à rien.
class EcranGlossaire extends ConsumerStatefulWidget {
  const EcranGlossaire({super.key, this.axe});

  final String? axe;

  @override
  ConsumerState<EcranGlossaire> createState() => _EtatGlossaire();
}

class _EtatGlossaire extends ConsumerState<EcranGlossaire> {
  final _champ = TextEditingController();
  String _q = '';
  Timer? _attente;

  @override
  void dispose() {
    _attente?.cancel();
    _champ.dispose();
    super.dispose();
  }

  void _saisie(String v) {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final notions = ref.watch(glossaireProvider((axe: widget.axe, q: _q)));

    return Scaffold(
      appBar: AppBar(title: const Texte('Les notions')),
      // Le grain du papier : le glossaire s'ouvre hors de la coque.
      body: FondPapier(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: TextField(
                  controller: _champ,
                  onChanged: _saisie,
                  // En pilule, comme la recherche : les deux champs cherchent dans
                  // le corpus et se reconnaissent à la même forme.
                  decoration: InputDecoration(
                    hintText: 'Une notion, un terme…',
                    fillColor: p.surface,
                    border: const OutlineInputBorder(borderRadius: Rayons.pilule, borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: Rayons.pilule, borderSide: BorderSide(color: p.trait)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: Rayons.pilule,
                      borderSide: BorderSide(color: p.accentTexte, width: 1.6),
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
                      child: IconeAscenda(Icone.loupe, taille: 19, couleur: p.accentTexte),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: _champ.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 19),
                            onPressed: () {
                              _champ.clear();
                              setState(() => _q = '');
                            },
                          ),
                  ),
                ),
              ),
              Expanded(
                child: notions.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(20),
                    child: SqueletteCarte(lignes: 5),
                  ),
                  error: (e, _) => EtatErreur(
                    erreur: e,
                    reessayer: () =>
                        ref.invalidate(glossaireProvider((axe: widget.axe, q: _q))),
                  ),
                  data: (liste) {
                    // Les notions ancrées dans le texte d'abord : ce sont les
                    // seules qui mènent quelque part.
                    final ancrees = liste.where((n) => (n['occurrences'] as int? ?? 0) > 0).toList();
                    final orphelines = liste.where((n) => (n['occurrences'] as int? ?? 0) == 0).toList();
                    if (liste.isEmpty) {
                      return const EtatMessage(
                        scene: Scene.loupeVide,
                        titre: 'Aucune notion',
                        texte: "Aucun terme du glossaire ne correspond. Essayez une "
                            "formulation plus courte.",
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
                      children: [
                        for (final (i, n) in ancrees.indexed) ...[
                          Apparition(rang: i, child: _LigneNotion(notion: n)),
                          const SizedBox(height: 10),
                        ],
                        if (orphelines.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const TitreSection(
                            'Nommées sans être définies dans le texte',
                            sousTitre: "Ces notions viennent des fiches de lecture. Aucun passage "
                                "du corpus ne les emploie, il n'y a donc rien à ouvrir.",
                          ),
                          const SizedBox(height: 12),
                          for (final n in orphelines) ...[
                            _LigneNotion(notion: n),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LigneNotion extends StatelessWidget {
  const _LigneNotion({required this.notion});
  final Map<String, dynamic> notion;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final n = notion['occurrences'] as int? ?? 0;
    final terme = '${notion['terme']}';
    final initiale = terme.trim().isEmpty ? '?' : terme.trim().characters.first.toUpperCase();
    final ancree = n > 0;
    // Une notion qui ne mène nulle part reste lisible mais s'efface : pas de
    // surface blanche, pas d'or, pas de chevron.
    return Surface(
      onTap: ancree ? () => context.push('/notion/${notion['id']}') : null,
      couleur: ancree ? null : p.surfaceCreuse.withValues(alpha: 0.5),
      ombre: ancree,
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      child: Row(
        children: [
          // La lettrine du dictionnaire : la première lettre du terme, encadrée
          // à l'encre comme en tête d'un chapitre.
          Lettrine(initiale, taille: 42, couleur: ancree ? p.accentTexte : p.attenue),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte(terme,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleMedium?.copyWith(color: ancree ? p.encre : p.attenue)),
                if ('${notion['definition'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Texte(
                    '${notion['definition']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
          if (ancree) ...[
            const SizedBox(width: 10),
            // Le nombre de passages, en folio : c'est ce qui dit si la notion
            // mène quelque part.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Texte('$n',
                    style: t.textTheme.titleMedium?.copyWith(color: p.accentTexte, fontSize: 16)),
                Texte(n > 1 ? 'passages' : 'passage',
                    style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 0.4)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Une notion et les passages qui la portent.
class EcranNotion extends ConsumerWidget {
  const EcranNotion({super.key, required this.notionId});

  final String notionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final notion = ref.watch(notionProvider(notionId));

    return Scaffold(
      appBar: AppBar(title: const Texte('Notion')),
      // Le grain du papier : la notice d'une notion s'ouvre hors de la coque.
      body: FondPapier(
        child: SafeArea(
          bottom: false,
          child: notion.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: SqueletteCarte(lignes: 4),
            ),
            error: (e, _) => EtatErreur(
              erreur: e,
              reessayer: () => ref.invalidate(notionProvider(notionId)),
            ),
            data: (d) {
              final occurrences =
                  ((d['occurrences'] as List?) ?? []).cast<Map<String, dynamic>>();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                children: [
                  if ('${d['axe_label'] ?? ''}'.isNotEmpty) ...[
                    EtiquetteCrochet('${d['axe_label']}'),
                    const SizedBox(height: 12),
                  ],
                  Texte('${d['terme']}', style: t.textTheme.headlineMedium?.copyWith(fontSize: 28)),
                  if ('${d['definition'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    // La définition comme l'entrée d'un dictionnaire : la lettrine
                    // du terme, puis le texte. On la relit, on ne la parcourt pas.
                    Surface(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Lettrine(
                            '${d['terme']}'.trim().isEmpty ? '?' : '${d['terme']}'.trim().characters.first,
                            taille: 46,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Texte('${d['definition']}',
                                style: t.textTheme.bodyLarge?.copyWith(
                                  fontFamily: t.textTheme.headlineSmall?.fontFamily,
                                  fontSize: 16,
                                  color: p.encre,
                                  height: 1.65,
                                )),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  TitreCourant(
                    occurrences.isEmpty ? 'aucun passage repéré' : 'où le corpus en parle',
                    folio: occurrences.isEmpty
                        ? null
                        : (occurrences.length > 1 ? '${occurrences.length} passages' : '1 passage'),
                  ),
                  const SizedBox(height: 14),
                  for (final (i, o) in occurrences.indexed) ...[
                    Apparition(rang: i, child: _CarteOccurrence(occurrence: o)),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 16),
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

class _CarteOccurrence extends StatelessWidget {
  const _CarteOccurrence({required this.occurrence});
  final Map<String, dynamic> occurrence;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final o = occurrence;
    // Le serveur marque le passage qui définit la notion, par opposition à
    // ceux qui l'emploient. C'est celui-là qu'on veut lire en premier, et il
    // arrive en tête : autant le dire.
    final definit = o['definition'] == true;
    final chapitreId = o['chapitre_id'];

    return Surface(
      // Un voile doré sur le passage qui définit : il se repère avant d'être lu.
      couleur: definit ? Color.alphaBlend(p.accentVoile, p.surface) : null,
      onTap: () => context.push(chapitreId == null
          ? '/ouvrage/${o['document_id']}'
          : '/lecture/${o['document_id']}/$chapitreId'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Texte('${o['ouvrage'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleMedium),
              ),
              if (definit) ...[
                const SizedBox(width: 8),
                const Pastille('la définit', icone: Icons.star_rounded),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Le titre courant de la page citée : le chapitre, puis le folio.
          TitreCourant(
            '${o['chapitre'] ?? ''}'.isNotEmpty ? '${o['chapitre']}' : 'dans le texte',
            folio: o['page'] != null ? 'p. ${o['page']}' : null,
          ),
          const SizedBox(height: 12),
          // L'extrait en exergue, marge à l'encre d'or.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 2, color: p.accentTexte.withValues(alpha: 0.55)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 2, 2),
                    child: Texte('${o['extrait'] ?? ''}',
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(
                          fontFamily: t.textTheme.headlineSmall?.fontFamily,
                          fontSize: 13.5,
                          color: p.texte,
                          height: 1.6,
                        )),
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
