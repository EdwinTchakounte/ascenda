import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../theme/icones.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import 'illustrations.dart';
import 'ui.dart';

/// Les quatre teintes que le serveur accepte pour un surlignage.
///
/// La liste vit ici et dans la contrainte de l'API. Elle est courte et stable :
/// une palette libre produirait, au bout de six mois, des surlignages de
/// quarante nuances dont aucune ne veut rien dire.
///
/// Relue à chaque appel : une table figée au premier accès garderait les
/// teintes du thème d'alors, et un surlignage fait en Ivoire resterait pâle une
/// fois passé en Nuit.
Map<String, Color> get teintesSurlignage => {
  'or': Couleurs.or,
  'sauge': Couleurs.sauge,
  'terracotta': Couleurs.terracotta,
  'ardoise': Couleurs.ardoise,
};

Color teinteDe(String? code) => teintesSurlignage[code] ?? Couleurs.or;

/// Le panneau des annotations d'un ouvrage : ce qu'on a surligné, ce qu'on a
/// noté, et de quoi le corriger ou l'effacer.
///
/// Ce sont des notes en marge, pas des fiches d'application : chacune garde sa
/// marge à l'encre, sa citation en Fraunces et son folio.
///
/// Jusqu'ici on pouvait écrire une note et plus jamais y toucher. Une note
/// fausse qu'on ne peut pas corriger vaut moins que pas de note du tout : on
/// finit par ne plus s'y fier.
class PanneauAnnotations extends ConsumerWidget {
  const PanneauAnnotations({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final notes = ref.watch(notesProvider(documentId));
    final surlignages = ref.watch(surlignagesProvider(documentId));

    final p = context.palette;
    final nbSurlignages = surlignages.valueOrNull?.length;
    final nbNotes = notes.valueOrNull?.length;

    // La poignée de la feuille vient du thème (`showDragHandle`) : la dessiner
    // ici aussi en montrait deux.
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                _Vignette(Icone.encrier, couleur: p.accentTexte),
                const SizedBox(width: 12),
                Expanded(
                  child: Texte('Vos annotations',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleLarge),
                ),
              ],
            ),
          ),
          // Deux onglets en segments arrondis : l'onglet actif est une pilule
          // dorée, dans le langage des filtres du reste de l'application.
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: p.surfaceCreuse, borderRadius: Rayons.pilule),
            child: TabBar(
              indicator: BoxDecoration(color: p.accent, borderRadius: Rayons.pilule),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: p.surAccent,
              unselectedLabelColor: p.texte,
              splashBorderRadius: Rayons.pilule,
              tabs: [
                Tab(height: 40, text: nbSurlignages == null ? 'Surlignages' : 'Surlignages ($nbSurlignages)'),
                Tab(height: 40, text: nbNotes == null ? 'Notes' : 'Notes ($nbNotes)'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              children: [
                _Liste(
                  contenu: surlignages,
                  vide: "Sélectionnez un passage dans le texte pour le surligner.",
                  scene: Scene.pageBlanche,
                  construire: (s) => _CarteSurlignage(
                    surlignage: s,
                    onSupprimer: () => _supprimerSurlignage(context, ref, '${s['id']}'),
                  ),
                ),
                _Liste(
                  contenu: notes,
                  vide: "Aucune note sur cet ouvrage pour l'instant.",
                  scene: Scene.pageBlanche,
                  construire: (n) => _CarteNote(
                    note: n,
                    onModifier: () => _modifierNote(context, ref, n),
                    onSupprimer: () => _supprimerNote(context, ref, '${n['id']}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _supprimerSurlignage(BuildContext context, WidgetRef ref, String id) async {
    if (!await _confirmer(context, 'Retirer ce surlignage ?')) return;
    try {
      await ref.read(clientApiProvider).delete('/surlignages/$id');
      ref.invalidate(surlignagesProvider(documentId));
    } catch (_) {
      if (context.mounted) _dire(context, "Le surlignage n'a pas pu être retiré.");
    }
  }

  Future<void> _supprimerNote(BuildContext context, WidgetRef ref, String id) async {
    if (!await _confirmer(context, 'Supprimer cette note ?')) return;
    try {
      await ref.read(clientApiProvider).delete('/notes/$id');
      ref.invalidate(notesProvider(documentId));
    } catch (_) {
      if (context.mounted) _dire(context, "La note n'a pas pu être supprimée.");
    }
  }

  Future<void> _modifierNote(
      BuildContext context, WidgetRef ref, Map<String, dynamic> note) async {
    final texte = await editerNote(context, initial: '${note['texte'] ?? note['body'] ?? ''}');
    if (texte == null || texte.isEmpty) return;
    // L'identifiant est sorti de l'interpolation : une apostrophe imbriquée
    // dans un littéral de chemin échappe au relevé des appels, et la
    // vérification de contrat ne voit plus la route.
    final id = '${note['id']}';
    try {
      await ref.read(clientApiProvider).patch('/notes/$id', corps: {'texte': texte});
      ref.invalidate(notesProvider(documentId));
    } catch (_) {
      if (context.mounted) _dire(context, "La note n'a pas pu être modifiée.");
    }
  }
}

/// La saisie d'une note, à la création comme à la correction.
///
/// Un seul formulaire pour les deux : ce qui distingue une correction d'une
/// création, c'est le texte déjà présent, rien d'autre.
Future<String?> editerNote(BuildContext context, {String initial = ''}) {
  final controleur = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Vignette(Icone.plume, couleur: c.palette.accentTexte),
              const SizedBox(width: 12),
              Expanded(
                child: Texte(initial.isEmpty ? 'Votre note' : 'Corriger la note',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(c).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Filet(redouble: true),
          const SizedBox(height: 14),
          TextField(
            controller: controleur,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: 'Ce que vous voulez retenir…',
              fillColor: c.palette.surfaceCreuse,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, controleur.text.trim()),
            icon: const Icon(Icons.check_rounded, size: 19),
            label: const Texte('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirmer(BuildContext context, String question) async {
  final oui = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Texte(question),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Texte('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Texte('Supprimer')),
      ],
    ),
  );
  return oui ?? false;
}

void _dire(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Texte(message)));
}

class _Liste extends StatelessWidget {
  const _Liste({required this.contenu, required this.vide, required this.scene, required this.construire});

  final AsyncValue<List<Map<String, dynamic>>> contenu;
  final String vide;

  /// La scène qui raconte l'absence : une page encore blanche.
  final Scene scene;
  final Widget Function(Map<String, dynamic>) construire;

  @override
  Widget build(BuildContext context) {
    return contenu.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(strokeWidth: 2.4),
      )),
      error: (e, _) => const _Vide(scene: Scene.sansReseau, texte: "Impossible de charger cette liste."),
      data: (liste) => liste.isEmpty
          ? _Vide(scene: scene, texte: vide)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              itemCount: liste.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: construire(liste[i]),
              ),
            ),
    );
  }
}

/// Une liste vide ou en échec, dite par une scène dessinée plutôt qu'une ligne
/// nue : une page blanche est un moment de la lecture, pas une panne.
class _Vide extends StatelessWidget {
  const _Vide({required this.scene, required this.texte});
  final Scene scene;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(36, 36, 36, 32),
      child: Column(
        children: [
          Illustration(scene, taille: 168),
          const SizedBox(height: 18),
          Texte(
            texte,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.attenue, height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// Une vignette d'encre : l'icône dessinée dans un cadre filetté.
class _Vignette extends StatelessWidget {
  const _Vignette(this.icone, {required this.couleur, this.taille = 40});
  final Icone icone;
  final Color couleur;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: p.sombre ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(taille * 0.3),
        border: Border.all(color: couleur.withValues(alpha: 0.32)),
      ),
      child: IconeAscenda(icone, taille: taille * 0.52, couleur: couleur),
    );
  }
}

class _CarteSurlignage extends StatelessWidget {
  const _CarteSurlignage({required this.surlignage, required this.onSupprimer});

  final Map<String, dynamic> surlignage;
  final VoidCallback onSupprimer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final teinte = teinteDe(surlignage['couleur'] as String?);
    final page = surlignage['page'];
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Le trait de la teinte choisie, en marge de la citation : c'est la
          // marque laissée dans la page.
          Container(
            width: 4,
            height: 44,
            margin: const EdgeInsets.only(top: 3, right: 14),
            decoration: BoxDecoration(color: teinte, borderRadius: Rayons.pilule),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En Fraunces, comme dans le lecteur : c'est le texte du livre.
                Texte('${surlignage['citation'] ?? ''}',
                    style: t.textTheme.bodyMedium?.copyWith(
                      fontFamily: t.textTheme.headlineSmall?.fontFamily,
                      fontSize: 15,
                      color: p.encre,
                      height: 1.6,
                    )),
                if (page != null) ...[
                  const SizedBox(height: 10),
                  const Filet(),
                  const SizedBox(height: 6),
                  Texte('p. $page',
                      style: t.textTheme.labelSmall
                          ?.copyWith(color: p.attenue, letterSpacing: 1)),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            color: p.attenue,
            tooltip: 'Retirer',
            onPressed: onSupprimer,
          ),
        ],
      ),
    );
  }
}

class _CarteNote extends StatelessWidget {
  const _CarteNote({
    required this.note,
    required this.onModifier,
    required this.onSupprimer,
  });

  final Map<String, dynamic> note;
  final VoidCallback onModifier;
  final VoidCallback onSupprimer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final page = note['page'];
    // Une note écrite en marge : le filet de la marge à gauche, la main du
    // lecteur à droite.
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 16, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Vignette(Icone.encrier, couleur: p.accentTexte, taille: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10, top: 4),
                  child: Texte('${note['texte'] ?? note['body'] ?? ''}',
                      style: t.textTheme.bodyMedium?.copyWith(height: 1.6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Padding(padding: EdgeInsets.only(left: 46, right: 10), child: Filet()),
          const SizedBox(height: 2),
          Row(
            children: [
              const SizedBox(width: 46),
              if (page != null)
                Texte('p. $page',
                    style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 1)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: p.attenue,
                tooltip: 'Corriger',
                onPressed: onModifier,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                color: p.attenue,
                tooltip: 'Supprimer',
                onPressed: onSupprimer,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
