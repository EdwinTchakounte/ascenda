import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/hors_ligne.dart';
import '../theme/icones.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import '../widgets/cartes.dart';
import '../widgets/etats.dart';
import '../widgets/invitation.dart';
import '../widgets/livre.dart';
import '../widgets/ui.dart';

/// La bibliothèque : une salle de lecture, pas une liste de résultats.
///
/// L'écran s'ouvre sur le rayon des volumes, puis donne les fiches. Les filtres
/// sont des étiquettes d'encre au-dessus d'un filet : ce qui trie le fonds se
/// lit comme l'appareil d'un catalogue, pas comme une barre d'outils.
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

  /// Le titre courant de la page : ce que le lecteur regarde en ce moment.
  /// Un pôle sélectionné porte son nom, pas celui de son premier sous-axe.
  String _libelleFiltre(List<Axe> liste) {
    if (_axe == null) return 'Tout le fonds';
    for (final a in liste) {
      if (a.slug == _axe) return a.label;
      if (a.poleSlug == _axe) return a.poleLabel ?? a.label;
    }
    return 'Sélection';
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final filtre = FiltreBiblio(
      axe: _axe,
      niveau: _niveau,
      recherche: _texte.length >= 2 ? _texte : null,
    );
    final ouvrages = ref.watch(bibliothequeProvider(filtre.a(_page)));
    final axes = ref.watch(axesProvider);
    final listeAxes = axes.valueOrNull ?? const <Axe>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 0, 0),
              child: Row(
                children: [
                  const BoutonMenu(),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Texte('Bibliothèque', style: t.textTheme.headlineMedium?.copyWith(fontSize: 28)),
                  ),
                  const AvatarCompte(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _recherche,
                      onChanged: (v) => setState(() {
                        _texte = v.trim();
                        _reinitialiser();
                      }),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Un titre, un auteur…',
                        prefixIcon: IconeAscenda(Icone.loupe, taille: 20, couleur: p.attenue),
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
                  ),
                  const SizedBox(width: 10),
                  // Chercher dans le texte des ouvrages est un autre geste que
                  // chercher un titre : il a son propre bouton, bien visible.
                  // La page ouverte plutôt que la loupe : on cherche dedans.
                  Tooltip(
                    message: 'Chercher dans le texte des livres',
                    child: Material(
                      color: p.heros,
                      borderRadius: Rayons.moyen,
                      child: InkWell(
                        borderRadius: Rayons.moyen,
                        onTap: () => context.push('/recherche?q=${Uri.encodeComponent(_texte)}'),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Center(
                            child: IconeAscenda(Icone.page, taille: 25, couleur: p.accentSurHeros),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
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
            if (_axe != null && !listeAxes.any((a) => a.poleSlug == _axe))
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: TextButton.icon(
                    onPressed: () => context.push('/axe/$_axe'),
                    icon: IconeAscenda(Icone.boussole, taille: 18, couleur: p.accentTexte),
                    label: const Texte("Par où commencer dans cet axe"),
                  ),
                ),
              ),
            SizedBox(
              height: 44,
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
            // Le filet qui ferme l'appareil de tri : dessous commence le fonds.
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 2, 20, 0),
              child: Filet(redouble: true),
            ),
            Expanded(
              child: ouvrages.when(
                loading: () => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                data: (page) {
                  // On empile les pages déjà reçues. Repartir de zéro à chaque
                  // chargement ramènerait le lecteur en haut de la liste.
                  if (page.page == 1) {
                    _recus
                      ..clear()
                      ..addAll(page.ouvrages);
                  } else if (_recus.length < page.page * parPageBiblio) {
                    _recus.addAll(page.ouvrages);
                  }
                  _total = page.total;
                  final liste = _recus;
                  return liste.isEmpty
                    ? const _RayonVide()
                    : RefreshIndicator(
                        color: p.accent,
                        onRefresh: () async => ref.invalidate(bibliothequeProvider(filtre.a(_page))),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                          // Une ligne de plus en queue : le bouton qui charge
                          // la suite, ou le mot de la fin.
                          itemCount: liste.length + 2,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            if (i == liste.length + 1) {
                              if (liste.length >= _total) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 16, bottom: 20),
                                  child: Column(
                                    children: [
                                      const Fleuron(),
                                      const SizedBox(height: 10),
                                      Texte(
                                        'Fin de la liste.',
                                        textAlign: TextAlign.center,
                                        style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                                      ),
                                    ],
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
                                  // Le rayon en tête : on reconnaît un fonds à
                                  // ses dos avant de lire ses notices. Sous
                                  // trois volumes, une tablette presque vide
                                  // ferait pauvre : on passe aux fiches.
                                  if (liste.length >= 3) ...[
                                    const SizedBox(height: 14),
                                    Rayon(
                                      volumes: [
                                        for (final o in liste.take(14))
                                          (
                                            titre: o.titre,
                                            axeSlug: o.axeSlug,
                                            marque: false,
                                            onTap: () => context.push('/ouvrage/${o.id}'),
                                          ),
                                      ],
                                      hauteur: 138,
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  TitreCourant(
                                    _libelleFiltre(listeAxes),
                                    folio: _total == 1
                                        ? '1 ouvrage'
                                        : '${liste.length} sur $_total ouvrages',
                                  ),
                                  const SizedBox(height: 2),
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

/// Un filtre : une étiquette d'encre pour les parcours, une petite capitale
/// soulignée pour les niveaux. Deux familles qui ne se confondent pas.
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

  /// Les niveaux se lisent comme les titres courants d'un catalogue, les
  /// parcours comme des étiquettes collées sur une boîte d'archives.
  final bool souligne;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    if (souligne) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: InkWell(
          borderRadius: Rayons.petit,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            // Le filet prend la largeur du mot : dans une rangée qui défile,
            // une colonne étirée réclamerait une largeur infinie.
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Texte(
                    libelle.toUpperCase(),
                    style: t.textTheme.labelSmall?.copyWith(
                      fontSize: 11.5,
                      letterSpacing: 1.4,
                      color: actif ? p.accentTexte : p.attenue,
                      fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 5),
                  // Le filet sous le niveau retenu : la marque d'un onglet de
                  // catalogue, sans pastille ni ombre.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 1.6,
                    color: actif ? p.accentTexte : p.encre.withValues(alpha: 0.10),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: Rayons.petit,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: actif ? p.encre : Colors.transparent,
            borderRadius: Rayons.petit,
            border: Border.all(color: actif ? p.encre : p.encre.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Texte(
                libelle,
                style: t.textTheme.labelLarge?.copyWith(
                  color: actif ? p.fond : p.texte,
                  fontSize: 13,
                  letterSpacing: 0.2,
                  fontWeight: actif ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (compte != null) ...[
                const SizedBox(width: 8),
                // Le nombre d'ouvrages comme un folio : chiffres tabulaires,
                // séparés du libellé par un filet vertical.
                Container(
                  width: 1,
                  height: 13,
                  color: (actif ? p.fond : p.encre).withValues(alpha: 0.30),
                ),
                const SizedBox(width: 8),
                Texte(
                  '$compte',
                  style: t.textTheme.labelSmall?.copyWith(
                    color: actif ? p.fond : p.accentTexte,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// Le fonds ne rend rien : un carton de catalogue, pas une icône barrée.
class _RayonVide extends StatelessWidget {
  const _RayonVide();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Fleuron(taille: 30),
              const SizedBox(height: 26),
              Texte(
                'Aucun ouvrage',
                textAlign: TextAlign.center,
                style: t.textTheme.headlineSmall?.copyWith(fontSize: 23),
              ),
              const SizedBox(height: 12),
              Texte(
                "Aucun titre ne correspond à ces critères. "
                "Essayez un autre axe ou effacez la recherche.",
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium?.copyWith(color: p.attenue, height: 1.6),
              ),
              const SizedBox(height: 26),
              const Fleuron(taille: 30),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sans réseau, la bibliothèque montre ce qui a été emporté. Sans cela, un
/// ouvrage gardé sur l'appareil n'avait aucune porte d'entrée en zone blanche.
///
/// Les volumes emportés gardent leur dos : en zone blanche, on retrouve le
/// livre qu'on a commencé à l'endroit exact où il se rangeait avant.
class _LivresEmportes extends ConsumerWidget {
  const _LivresEmportes({required this.reessayer});
  final VoidCallback reessayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final packs = ref.watch(packsProvider).valueOrNull ?? {};
    if (packs.isEmpty) return EtatErreur(erreur: const HorsLigne(), reessayer: reessayer);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        const EtiquetteCrochet('sans réseau'),
        const SizedBox(height: 12),
        Texte(
          'Pas de connexion. Vos ouvrages emportés restent lisibles.',
          style: t.textTheme.bodyMedium?.copyWith(color: p.texte, height: 1.5),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: reessayer, child: const Texte('Réessayer')),
        ),
        const SizedBox(height: 10),
        TitreCourant(
          'sur l\'appareil',
          folio: packs.length == 1 ? '1 volume' : '${packs.length} volumes',
        ),
        const SizedBox(height: 14),
        for (final pack in packs.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Surface(
              onTap: () => context.push('/ouvrage/${pack.documentId}'),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Le signet dépasse : ce volume est sur l'appareil.
                  DosLivre(titre: pack.titre, hauteur: 78, largeur: 36, marque: true),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Texte(
                          pack.titre,
                          style: t.textTheme.titleLarge?.copyWith(fontSize: 16.5, height: 1.28),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        const Filet(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconeAscenda(Icone.signet, taille: 14, couleur: p.succes),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Texte(
                                '${pack.compteurs['chapitres'] ?? 0} chapitres · ${pack.poids}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.labelSmall?.copyWith(color: p.attenue),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
