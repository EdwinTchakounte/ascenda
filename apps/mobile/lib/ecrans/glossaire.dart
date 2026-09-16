import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';
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
      body: SafeArea(
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
                  prefixIcon: Icon(Icons.search_rounded, size: 21, color: p.accentTexte),
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
                      icone: Icons.search_off_rounded,
                      titre: 'Aucune notion',
                      texte: "Aucun terme du glossaire ne correspond. Essayez une "
                          "formulation plus courte.",
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
                    children: [
                      for (final n in ancrees) ...[
                        _LigneNotion(notion: n),
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
          // L'initiale en Fraunces, comme une lettrine de dictionnaire.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ancree ? p.accentVoile : p.surfaceCreuse,
              borderRadius: Rayons.moyen,
            ),
            alignment: Alignment.center,
            child: Texte(initiale,
                style: t.textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                  color: ancree ? p.accentTexte : p.attenue,
                )),
          ),
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
            Pastille('$n', icone: Icons.format_quote_rounded),
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
      body: SafeArea(
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
                  Surtitre('${d['axe_label']}'),
                  const SizedBox(height: 8),
                ],
                Texte('${d['terme']}', style: t.textTheme.headlineMedium?.copyWith(fontSize: 28)),
                if ('${d['definition'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  // La définition comme un extrait encadré d'un filet doré : on
                  // la relit, on ne la parcourt pas.
                  Surface(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 3,
                          height: 22,
                          margin: const EdgeInsets.only(top: 3, right: 14),
                          decoration: BoxDecoration(color: p.accent, borderRadius: Rayons.pilule),
                        ),
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
                TitreSection(
                  occurrences.isEmpty
                      ? 'Aucun passage repéré'
                      : 'Où le corpus en parle',
                ),
                const SizedBox(height: 12),
                for (final o in occurrences) ...[
                  _CarteOccurrence(occurrence: o),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
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
          const SizedBox(height: 3),
          Row(
            children: [
              if ('${o['chapitre'] ?? ''}'.isNotEmpty)
                Flexible(
                  child: Texte('${o['chapitre']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.labelSmall?.copyWith(color: p.attenue)),
                ),
              if (o['page'] != null) ...[
                const SizedBox(width: 8),
                Texte('p. ${o['page']}',
                    style: t.textTheme.labelSmall?.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: definit ? p.surface.withValues(alpha: 0.7) : p.surfaceCreuse,
              borderRadius: Rayons.moyen,
            ),
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
        ],
      ),
    );
  }
}
