import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';

/// Les quatre teintes que le serveur accepte pour un surlignage.
///
/// La liste vit ici et dans la contrainte de l'API. Elle est courte et stable :
/// une palette libre produirait, au bout de six mois, des surlignages de
/// quarante nuances dont aucune ne veut rien dire.
const Map<String, Color> teintesSurlignage = {
  'or': Couleurs.or,
  'sauge': Couleurs.sauge,
  'terracotta': Couleurs.terracotta,
  'ardoise': Couleurs.ardoise,
};

Color teinteDe(String? code) => teintesSurlignage[code] ?? Couleurs.or;

/// Le panneau des annotations d'un ouvrage : ce qu'on a surligné, ce qu'on a
/// noté, et de quoi le corriger ou l'effacer.
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

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Couleurs.grisChaud.withValues(alpha: 0.3),
              borderRadius: BorderRadius.zero,
            ),
          ),
          const SizedBox(height: 12),
          Text('Vos annotations', style: t.textTheme.titleLarge),
          const TabBar(
            tabs: [Tab(text: 'Surlignages'), Tab(text: 'Notes')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _Liste(
                  contenu: surlignages,
                  vide: "Sélectionnez un passage dans le texte pour le surligner.",
                  construire: (s) => _CarteSurlignage(
                    surlignage: s,
                    onSupprimer: () => _supprimerSurlignage(context, ref, '${s['id']}'),
                  ),
                ),
                _Liste(
                  contenu: notes,
                  vide: "Aucune note sur cet ouvrage pour l'instant.",
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
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(initial.isEmpty ? 'Votre note' : 'Corriger la note',
              style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: controleur,
            autofocus: true,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Ce que vous voulez retenir…'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.pop(c, controleur.text.trim()),
            child: const Text('Enregistrer'),
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
      content: Text(question),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
      ],
    ),
  );
  return oui ?? false;
}

void _dire(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _Liste extends StatelessWidget {
  const _Liste({required this.contenu, required this.vide, required this.construire});

  final AsyncValue<List<Map<String, dynamic>>> contenu;
  final String vide;
  final Widget Function(Map<String, dynamic>) construire;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return contenu.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(strokeWidth: 2.4),
      )),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text("Impossible de charger cette liste.",
            style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud)),
      ),
      data: (liste) => liste.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
              child: Text(
                vide,
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: Couleurs.grisChaud, height: 1.6),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: liste.length,
              itemBuilder: (_, i) => construire(liste[i]),
            ),
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
    final teinte = teinteDe(surlignage['couleur'] as String?);
    final page = surlignage['page'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: teinte.withValues(alpha: 0.09),
        borderRadius: BorderRadius.zero,
        border: Border(left: BorderSide(color: teinte, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${surlignage['citation'] ?? ''}',
                    style: t.textTheme.bodyMedium?.copyWith(height: 1.6)),
                if (page != null) ...[
                  const SizedBox(height: 6),
                  Text('Page $page',
                      style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            color: Couleurs.grisChaud,
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
    final page = note['page'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Couleurs.traitClair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('${note['texte'] ?? note['body'] ?? ''}',
                style: t.textTheme.bodyMedium?.copyWith(height: 1.6)),
          ),
          Row(
            children: [
              if (page != null)
                Text('Page $page',
                    style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: Couleurs.grisChaud,
                tooltip: 'Corriger',
                onPressed: onModifier,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                color: Couleurs.grisChaud,
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
