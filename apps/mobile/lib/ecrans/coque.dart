import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/cercle.dart';
import '../etat/hors_ligne.dart';
import '../etat/session.dart';
import '../theme/icones.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import '../widgets/selecteur_theme.dart';
import '../widgets/ui.dart';
import 'auth.dart';

/// La coque : quatre onglets en bas, et un tiroir pour tout le reste.
class CoqueAscenda extends ConsumerWidget {
  const CoqueAscenda({super.key, required this.coque});

  final StatefulNavigationShell coque;

  static const _onglets = [
    (icone: Icone.soleil, libelle: 'Le jour'),
    (icone: Icone.volumes, libelle: 'Les livres'),
    (icone: Icone.plume, libelle: "L'agent"),
    (icone: Icone.pousse, libelle: 'Le chemin'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Scaffold(
      key: cleCoque,
      drawer: const TiroirAscenda(),
      drawerEdgeDragWidth: 28,
      body: FondPapier(child: coque),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: p.trait)),
          boxShadow: [
            BoxShadow(color: p.ombre.withValues(alpha: p.sombre ? 0.4 : 0.06), blurRadius: 24, offset: const Offset(0, -6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: Stack(
            children: [
              // Le signet : un filet d'or glissé sous l'onglet ouvert.
              AnimatedAlign(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                alignment: Alignment(-1 + 2 * coque.currentIndex / (_onglets.length - 1), -1),
                child: FractionallySizedBox(
                  widthFactor: 1 / _onglets.length,
                  child: Center(
                    child: Container(
                      width: 46,
                      height: 3,
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                        boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.45), blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
              ),
              NavigationBar(
                backgroundColor: Colors.transparent,
                selectedIndex: coque.currentIndex,
                animationDuration: const Duration(milliseconds: 380),
                onDestinationSelected: (i) => coque.goBranch(i, initialLocation: i == coque.currentIndex),
                destinations: [
                  for (final (i, o) in _onglets.indexed)
                    NavigationDestination(
                      icon: IconeAscenda(o.icone, taille: 25, couleur: p.attenue),
                      selectedIcon: IconeAscenda(o.icone, taille: 25, couleur: p.accentTexte, pleine: true, epaisseur: 1.9),
                      label: o.libelle,
                      tooltip: o.libelle,
                      key: ValueKey('onglet-$i'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le tiroir : le compte en tête, les espaces secondaires, puis le thème.
class TiroirAscenda extends ConsumerWidget {
  const TiroirAscenda({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final u = session.utilisateur;
    final connecte = session.connecte;
    final attente = connecte ? (ref.watch(cercleMoiProvider).valueOrNull?.compteurs.total ?? 0) : 0;
    final emportes = ref.watch(packsProvider).valueOrNull?.length ?? 0;

    void aller(String chemin) {
      Navigator.of(context).pop();
      context.push(chemin);
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                children: [
                  // L'en-tête : la carte du compte, sur le dégradé du thème.
                  SurfaceHeros(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    onTap: connecte ? () => aller('/profil') : null,
                    child: connecte
                        ? Row(
                            children: [
                              const AvatarCompte(taille: 50, ouvrirProfil: false),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Texte(
                                      u?.nom ?? 'Votre compte',
                                      style: t.textTheme.titleLarge?.copyWith(color: p.surHeros, fontSize: 19),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Pastille(
                                      u?.accesComplet == true ? 'Ascension' : 'Formule gratuite',
                                      couleur: p.accentSurHeros,
                                    ),
                                  ],
                                ),
                              ),
                              IconeAscenda(Icone.fleche, taille: 20, couleur: p.surHerosDoux),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const MarqueAscenda(taille: 40),
                              const SizedBox(height: 12),
                              Texte('Lisez avec un plan, à votre rythme.',
                                  style: t.textTheme.titleMedium?.copyWith(color: p.surHeros)),
                              const SizedBox(height: 14),
                              FilledButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  context.go('/bienvenue');
                                },
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                                child: const Texte('Se connecter'),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 18),
                  if (connecte) ...[
                    const _Rubrique('Mon espace'),
                    _Entree(icone: Icone.lecteur, libelle: 'Profil et compte', onTap: () => aller('/profil')),
                    _Entree(
                      icone: Icone.cercle,
                      libelle: 'Cercle de lecture',
                      compteur: attente,
                      onTap: () {
                        rafraichirCercle(ref);
                        aller('/cercle');
                      },
                    ),
                    _Entree(icone: Icone.cartes, libelle: 'Révisions', onTap: () => aller('/revision')),
                    _Entree(
                      icone: Icone.boussole,
                      libelle: 'Nouveau parcours',
                      detail: 'Refaire le diagnostic',
                      onTap: () => aller('/diagnostic'),
                    ),
                  ],
                  const _Rubrique('Bibliothèque'),
                  _Entree(
                    icone: Icone.signet,
                    libelle: 'Livres hors ligne',
                    detail: emportes == 0 ? null : '$emportes sur l\'appareil',
                    onTap: () => aller('/hors-ligne'),
                  ),
                  _Entree(icone: Icone.clef, libelle: 'Notions clés', onTap: () => aller('/notions')),
                  _Entree(icone: Icone.loupe, libelle: 'Chercher dans les livres', onTap: () => aller('/recherche')),
                  if (connecte) ...[
                    const _Rubrique('Ascension'),
                    _Entree(
                      icone: Icone.sceau,
                      libelle: 'Offre Ascension',
                      accent: true,
                      onTap: () => aller('/abonnement'),
                    ),
                    _Entree(icone: Icone.jeton, libelle: 'Codes et avantages', onTap: () => aller('/codes')),
                  ],
                  const _Rubrique('Apparence'),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 6, 6, 4),
                    child: SelecteurTheme(compact: true),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.trait),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(
                children: [
                  const MarqueAscenda(taille: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Texte('Learn. Grow. Become.',
                        style: t.textTheme.labelSmall?.copyWith(color: p.attenue)),
                  ),
                  if (connecte)
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await ref.read(sessionProvider.notifier).deconnexion();
                      },
                      style: TextButton.styleFrom(foregroundColor: p.alerte),
                      icon: const IconeAscenda(Icone.fleche, taille: 18),
                      label: const Texte('Sortir'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rubrique extends StatelessWidget {
  const _Rubrique(this.titre);
  final String titre;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Row(
          children: [
            Surtitre(titre, couleur: context.palette.attenue),
            const SizedBox(width: 10),
            const Expanded(child: Filet()),
          ],
        ),
      );
}

class _Entree extends StatelessWidget {
  const _Entree({
    required this.icone,
    required this.libelle,
    required this.onTap,
    this.detail,
    this.compteur = 0,
    this.accent = false,
  });

  final Icone icone;
  final String libelle;
  final String? detail;
  final int compteur;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: Rayons.moyen,
        child: InkWell(
          borderRadius: Rayons.moyen,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: (accent ? p.accentTexte : p.texte).withValues(alpha: 0.28)),
                    color: (accent ? p.accentTexte : p.texte).withValues(alpha: p.sombre ? 0.10 : 0.05),
                  ),
                  child: IconeAscenda(icone, taille: 21, couleur: accent ? p.accentTexte : p.texte),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Texte(libelle,
                          style: t.textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            color: accent ? p.accentTexte : p.encre,
                          )),
                      if (detail != null)
                        Texte(detail!, style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.3)),
                    ],
                  ),
                ),
                if (compteur > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: p.alerte, borderRadius: Rayons.pilule),
                    child: Texte('$compteur',
                        style: t.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
