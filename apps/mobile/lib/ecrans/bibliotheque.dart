import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../widgets/cartes.dart';
import '../widgets/etats.dart';
import '../widgets/invitation.dart';

class EcranBibliotheque extends ConsumerStatefulWidget {
  const EcranBibliotheque({super.key});

  @override
  ConsumerState<EcranBibliotheque> createState() => _EcranBibliothequeState();
}

class _EcranBibliothequeState extends ConsumerState<EcranBibliotheque> {
  final _recherche = TextEditingController();
  String? _axe;
  String? _niveau;
  String _texte = '';

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final filtre = FiltreBiblio(
      axe: _axe,
      niveau: _niveau,
      recherche: _texte.length >= 2 ? _texte : null,
    );
    final ouvrages = ref.watch(bibliothequeProvider(filtre));
    final axes = ref.watch(axesProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bibliothèque', style: t.textTheme.headlineSmall),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _recherche,
                    onChanged: (v) => setState(() => _texte = v.trim()),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Un titre, un auteur…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 21),
                      helperText: 'Filtre les titres et les auteurs.',
                      suffixIcon: _texte.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 19),
                              onPressed: () {
                                _recherche.clear();
                                setState(() => _texte = '');
                              },
                            ),
                    ),
                  ),
                  // Le champ ci-dessus ne regarde que les titres et les
                  // auteurs. Chercher dans le texte des ouvrages est un autre
                  // geste, et il mérite d'être proposé plutôt que deviné.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => context.push(
                        '/recherche?q=${Uri.encodeComponent(_texte)}',
                      ),
                      icon: const Icon(Icons.travel_explore_rounded, size: 18),
                      label: const Text('Chercher dans le texte des livres'),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 56,
              child: axes.maybeWhen(
                data: (liste) => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  children: [
                    _Filtre(
                      libelle: 'Tous',
                      actif: _axe == null,
                      onTap: () => setState(() => _axe = null),
                    ),
                    for (final a in liste)
                      _Filtre(
                        libelle: a.label,
                        compte: a.nbOuvrages,
                        actif: _axe == a.slug,
                        onTap: () => setState(() => _axe = _axe == a.slug ? null : a.slug),
                      ),
                  ],
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final n in niveaux.entries)
                    _Filtre(
                      libelle: n.value,
                      actif: _niveau == n.key,
                      onTap: () => setState(() => _niveau = _niveau == n.key ? null : n.key),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ouvrages.when(
                loading: () => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: 5,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, _) => const SqueletteCarte(lignes: 2),
                ),
                error: (e, _) => EtatErreur(
                  erreur: e,
                  reessayer: () => ref.invalidate(bibliothequeProvider(filtre)),
                ),
                data: (liste) => liste.isEmpty
                    ? const EtatMessage(
                        icone: Icons.search_off_rounded,
                        titre: 'Aucun ouvrage',
                        texte: "Aucun titre ne correspond à ces critères. "
                            "Essayez un autre axe ou effacez la recherche.",
                      )
                    : RefreshIndicator(
                        color: Couleurs.or,
                        onRefresh: () async => ref.invalidate(bibliothequeProvider(filtre)),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          itemCount: liste.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const InvitationCompte(
                                    raison: "Ces 78 ouvrages sont consultables librement. "
                                        "Avec un compte, ASCENDA les découpe en séances "
                                        "que vous pouvez tenir, et vous interroge sur ce "
                                        "que vous lisez.",
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 14, bottom: 4),
                                    child: Text(
                                      liste.length == 1
                                          ? '1 ouvrage'
                                          : '${liste.length} ouvrages',
                                      style: t.textTheme.bodySmall
                                          ?.copyWith(color: Couleurs.grisChaud),
                                    ),
                                  ),
                                ],
                              );
                            }
                            final o = liste[i - 1];
                            return CarteOuvrage(
                              ouvrage: o,
                              onTap: () => context.push('/ouvrage/${o.id}'),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filtre extends StatelessWidget {
  const _Filtre({
    required this.libelle,
    required this.actif,
    required this.onTap,
    this.compte,
  });

  final String libelle;
  final bool actif;
  final VoidCallback onTap;
  final int? compte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: actif ? Couleurs.or.withValues(alpha: 0.12) : t.colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: actif ? Couleurs.or : (t.dividerTheme.color ?? Couleurs.traitClair),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                libelle,
                style: t.textTheme.labelLarge?.copyWith(
                  color: actif ? Couleurs.orTexte : Couleurs.grisChaud,
                  fontSize: 13,
                ),
              ),
              if (compte != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$compte',
                  style: t.textTheme.labelSmall?.copyWith(
                    color: actif ? Couleurs.orTexte : Couleurs.grisChaud,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
