import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/hors_ligne.dart';
import '../theme/couleurs.dart';
import '../widgets/cartes.dart';
import '../widgets/etats.dart';
import '../widgets/invitation.dart';
import '../theme/texte.dart';

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

  /// La page demandée, et ce qui a déjà été reçu. Changer un filtre repart de
  /// la première page : garder la page huit d'une liste devenue courte
  /// afficherait un vide inexplicable.
  int _page = 1;
  int _total = 0;
  final List<Ouvrage> _recus = [];

  void _reinitialiser() {
    _page = 1;
    _recus.clear();
  }

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
    final ouvrages = ref.watch(bibliothequeProvider(filtre.a(_page)));
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
                  Texte('Bibliothèque', style: t.textTheme.headlineMedium?.copyWith(fontSize: 30)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _recherche,
                    onChanged: (v) => setState(() {
                      _texte = v.trim();
                      _reinitialiser();
                    }),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Un titre, un auteur…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 21),
                      suffixIcon: _texte.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 19),
                              onPressed: () {
                                _recherche.clear();
                                setState(() {
                                  _texte = '';
                                  _reinitialiser();
                                });
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
                      label: const Texte('Chercher dans le texte des livres'),
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
                      onTap: () => setState(() {
                        _axe = null;
                        _reinitialiser();
                      }),
                    ),
                    // Un pôle tient en une pastille ; ses sous-axes s'ouvrent dessous.
                    for (final g in regrouperParPole(liste))
                      if (g.estPole)
                        _Filtre(
                          libelle: g.poleLabel!,
                          actif: _axe == g.poleSlug || g.axes.any((a) => a.slug == _axe),
                          onTap: () => setState(() {
                            _axe = _axe == g.poleSlug ? null : g.poleSlug;
                            _reinitialiser();
                          }),
                        )
                      else
                        _Filtre(
                          libelle: g.axes.first.label,
                          compte: g.axes.first.nbOuvrages,
                          actif: _axe == g.axes.first.slug,
                          onTap: () => setState(() {
                            _axe = _axe == g.axes.first.slug ? null : g.axes.first.slug;
                            _reinitialiser();
                          }),
                        ),
                  ],
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            if (axes.valueOrNull case final liste?)
              for (final g in regrouperParPole(liste))
                if (g.estPole && (_axe == g.poleSlug || g.axes.any((a) => a.slug == _axe)))
                  SizedBox(
                    height: 48,
                    child: ListView(
                      key: const Key('sous-axes'),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      children: [
                        for (final a in g.axes)
                          _Filtre(
                            libelle: a.label,
                            actif: _axe == a.slug,
                            onTap: () => setState(() {
                              // Retirer un sous-axe revient au pôle, pas à « Tous ».
                              _axe = _axe == a.slug ? g.poleSlug : a.slug;
                              _reinitialiser();
                            }),
                          ),
                      ],
                    ),
                  ),
            // Un axe sélectionné devient une porte. Le filtre dit ce qu'on
            // retire ; la fiche d'axe dit dans quel ordre lire ce qui reste.
            // Un pôle n'a pas de fiche à lui : la porte s'ouvre sur un sous-axe.
            if (_axe != null && !(axes.valueOrNull ?? const <Axe>[]).any((a) => a.poleSlug == _axe))
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: TextButton.icon(
                    onPressed: () => context.push('/axe/$_axe'),
                    icon: const Icon(Icons.route_outlined, size: 18),
                    label: const Texte("Par où commencer dans cet axe"),
                  ),
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
                      souligne: true,
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
                error: (e, _) => e is HorsLigne
                    ? _LivresEmportes(
                        reessayer: () => ref.invalidate(bibliothequeProvider(filtre.a(_page))),
                      )
                    : EtatErreur(
                        erreur: e,
                        reessayer: () => ref.invalidate(bibliothequeProvider(filtre.a(_page))),
                      ),
                data: (p) {
                  // On empile les pages déjà reçues. Repartir de zéro à chaque
                  // chargement ramènerait le lecteur en haut de la liste.
                  if (p.page == 1) {
                    _recus
                      ..clear()
                      ..addAll(p.ouvrages);
                  } else if (_recus.length < p.page * parPageBiblio) {
                    _recus.addAll(p.ouvrages);
                  }
                  _total = p.total;
                  final liste = _recus;
                  return liste.isEmpty
                    ? const EtatMessage(
                        icone: Icons.search_off_rounded,
                        titre: 'Aucun ouvrage',
                        texte: "Aucun titre ne correspond à ces critères. "
                            "Essayez un autre axe ou effacez la recherche.",
                      )
                    : RefreshIndicator(
                        color: Couleurs.or,
                        onRefresh: () async => ref.invalidate(bibliothequeProvider(filtre.a(_page))),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          // Une ligne de plus en queue : le bouton qui charge
                          // la suite, ou le mot de la fin.
                          itemCount: liste.length + 2,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            if (i == liste.length + 1) {
                              if (liste.length >= _total) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 10, bottom: 20),
                                  child: Texte(
                                    'Fin de la liste.',
                                    textAlign: TextAlign.center,
                                    style: t.textTheme.bodySmall
                                        ?.copyWith(color: Couleurs.grisChaud),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6, bottom: 20),
                                child: OutlinedButton(
                                  onPressed: () => setState(() => _page += 1),
                                  child: Texte(
                                    'Charger la suite (${_total - liste.length} restants)',
                                  ),
                                ),
                              );
                            }
                            if (i == 0) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const InvitationCompte(
                                    raison: "Le corpus est consultable librement. "
                                        "Avec un compte, ASCENDA le découpe en séances "
                                        "que vous pouvez tenir, et vous interroge sur ce "
                                        "que vous lisez.",
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 14, bottom: 4),
                                    child: Texte(
                                      _total == 1
                                          ? '1 ouvrage'
                                          : '${liste.length} sur $_total ouvrages',
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

class _Filtre extends StatelessWidget {
  const _Filtre({
    required this.libelle,
    required this.actif,
    required this.onTap,
    this.compte,
    this.souligne = false,
  });

  final String libelle;
  final bool actif;
  final VoidCallback onTap;
  final int? compte;

  /// Les niveaux se lisent comme des onglets soulignés, les parcours comme des
  /// pastilles : deux familles de filtres qui ne se confondent pas.
  final bool souligne;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final encre = t.colorScheme.onSurface;
    // En clair, le filtre actif est à l'encre ; en sombre, un aplat d'encre
    // disparaîtrait dans le fond, il passe à l'or.
    final sombre = t.brightness == Brightness.dark;
    final plein = sombre ? Couleurs.orClair : Couleurs.nuit;
    final surPlein = sombre ? Couleurs.nuitProfond : Colors.white;
    if (souligne) {
      return InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 18),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: actif ? Couleurs.or : Colors.transparent, width: 2),
            ),
          ),
          child: Texte(
            libelle,
            style: t.textTheme.labelLarge?.copyWith(
              fontSize: 13.5,
              color: actif ? encre : Couleurs.grisChaud,
              fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: actif ? plein : t.colorScheme.surface,
            border: Border.all(color: actif ? plein : encre.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Texte(
                libelle,
                style: t.textTheme.labelLarge?.copyWith(
                  color: actif ? surPlein : encre.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: actif ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (compte != null) ...[
                const SizedBox(width: 7),
                Texte(
                  '$compte',
                  style: t.textTheme.labelSmall?.copyWith(
                    color: actif ? (sombre ? const Color(0xFF4A3A10) : Couleurs.orClair) : Couleurs.grisChaud,
                    fontWeight: FontWeight.w600,
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


/// Sans réseau, la bibliothèque montre ce qui a été emporté. Sans cela, un
/// ouvrage gardé sur l'appareil n'avait aucune porte d'entrée en zone blanche.
class _LivresEmportes extends ConsumerWidget {
  const _LivresEmportes({required this.reessayer});
  final VoidCallback reessayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final packs = ref.watch(packsProvider).valueOrNull ?? {};
    if (packs.isEmpty) return EtatErreur(erreur: const HorsLigne(), reessayer: reessayer);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 18, color: Couleurs.grisChaud),
            const SizedBox(width: 8),
            Expanded(
              child: Texte('Pas de connexion. Vos ouvrages emportés restent lisibles.',
                  style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud)),
            ),
            TextButton(onPressed: reessayer, child: const Texte('Réessayer')),
          ],
        ),
        const SizedBox(height: 12),
        for (final p in packs.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: t.colorScheme.surface,
              child: InkWell(
                onTap: () => context.push('/ouvrage/${p.documentId}'),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.offline_pin_rounded, size: 20, color: Couleurs.sauge),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Texte(p.titre,
                                style: t.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Texte('${p.compteurs['chapitres'] ?? 0} chapitres · ${p.poids}',
                                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 20, color: Couleurs.grisChaud),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
