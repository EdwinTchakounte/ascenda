import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';

/// La recherche dans le texte des 78 ouvrages.
///
/// Elle cherche dans ce que les livres disent, pas seulement dans leurs titres.
/// Deux voies fusionnées : les mots exacts, qui trouvent un nom propre ou une
/// date, et le sens, qui trouve un passage qui parle de la même chose sans
/// employer les mêmes termes. C'est cette seconde voie qui répond à une
/// question posée avec ses propres mots.
class EcranRecherche extends ConsumerStatefulWidget {
  const EcranRecherche({super.key, this.initiale});

  final String? initiale;

  @override
  ConsumerState<EcranRecherche> createState() => _EtatRecherche();
}

class _EtatRecherche extends ConsumerState<EcranRecherche> {
  late final TextEditingController _champ =
      TextEditingController(text: widget.initiale ?? '');

  /// Ce qui est réellement envoyé au serveur, une fois la frappe retombée.
  String _requete = '';
  Timer? _attente;

  /// Interroger à chaque touche ferait une requête par lettre. Trois cents
  /// millisecondes suffisent à distinguer une pause d'une frappe continue.
  static const _repos = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _requete = (widget.initiale ?? '').trim();
  }

  @override
  void dispose() {
    _attente?.cancel();
    _champ.dispose();
    super.dispose();
  }

  void _saisie(String v) {
    _attente?.cancel();
    _attente = Timer(_repos, () {
      if (mounted) setState(() => _requete = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final assez = _requete.length >= 3;
    final resultats = ref.watch(rechercheProvider(_requete));
    final suggestions = ref.watch(suggestionsProvider(_requete));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _champ,
          autofocus: widget.initiale == null,
          onChanged: _saisie,
          onSubmitted: (v) => setState(() => _requete = v.trim()),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Une idée, une question, un nom…',
            border: InputBorder.none,
            suffixIcon: _champ.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () {
                      _champ.clear();
                      setState(() => _requete = '');
                    },
                  ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: !assez
            ? const EtatMessage(
                icone: Icons.travel_explore_rounded,
                titre: 'Chercher dans les livres',
                texte: "Trois lettres suffisent. ASCENDA cherche dans le texte des "
                    "78 ouvrages, pas seulement dans leurs titres : posez votre "
                    "question avec vos propres mots.",
              )
            : resultats.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: SqueletteCarte(lignes: 4),
                ),
                error: (e, _) => EtatErreur(
                  erreur: e,
                  reessayer: () => ref.invalidate(rechercheProvider(_requete)),
                ),
                data: (d) {
                  final liste = ((d['resultats'] as List?) ?? [])
                      .cast<Map<String, dynamic>>();
                  final ouvrages = suggestions.valueOrNull ?? const [];
                  if (liste.isEmpty && ouvrages.isEmpty) {
                    return const EtatMessage(
                      icone: Icons.search_off_rounded,
                      titre: 'Rien trouvé',
                      texte: "Aucun passage du corpus ne correspond. Essayez d'autres "
                          "mots, ou une formulation plus large.",
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      if (ouvrages.isNotEmpty) ...[
                        Text('Ouvrages', style: t.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        for (final o in ouvrages.take(4))
                          _LigneOuvrage(ouvrage: o),
                        const SizedBox(height: 22),
                      ],
                      if (liste.isNotEmpty) ...[
                        Row(
                          children: [
                            Text('Dans le texte', style: t.textTheme.titleSmall),
                            const Spacer(),
                            _Mode(mode: '${d['mode'] ?? ''}'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final r in liste) _CarteResultat(resultat: r),
                      ],
                    ],
                  );
                },
              ),
      ),
    );
  }
}

/// Par quelle voie la réponse est venue.
///
/// Le dire coûte une ligne et évite un malentendu : tant que le corpus n'est
/// pas vectorisé, la recherche est en plein texte, et un lecteur qui l'ignore
/// croit que le moteur comprend mal alors qu'il ne fait que chercher des mots.
class _Mode extends StatelessWidget {
  const _Mode({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context) {
    final libelle = switch (mode) {
      'hybride' => 'mots et sens',
      'semantique' => 'par le sens',
      'plein_texte' => 'par les mots',
      _ => '',
    };
    if (libelle.isEmpty) return const SizedBox.shrink();
    return Text(
      libelle,
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: Couleurs.grisChaud),
    );
  }
}

class _LigneOuvrage extends StatelessWidget {
  const _LigneOuvrage({required this.ouvrage});
  final Map<String, dynamic> ouvrage;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final auteurs = ((ouvrage['auteurs'] as List?) ?? []).join(', ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.menu_book_outlined, size: 21, color: Couleurs.orTexte),
      title: Text('${ouvrage['titre']}',
          maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium),
      subtitle: auteurs.isEmpty
          ? null
          : Text(auteurs,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
      onTap: () => context.push('/ouvrage/${ouvrage['id']}'),
    );
  }
}

class _CarteResultat extends StatelessWidget {
  const _CarteResultat({required this.resultat});
  final Map<String, dynamic> resultat;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = resultat;
    final page = r['page'];
    final chapitreId = r['chapitre_id'];
    final documentId = '${r['document_id']}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Couleurs.traitClair),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // Sans chapitre identifié, on ouvre la fiche de l'ouvrage : mieux
          // vaut arriver sur le livre que sur un écran vide.
          onTap: () => context.push(chapitreId == null
              ? '/ouvrage/$documentId'
              : '/lecture/$documentId/$chapitreId'),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['ouvrage'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if ('${r['chapitre'] ?? ''}'.isNotEmpty)
                      Flexible(
                        child: Text('${r['chapitre']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.labelSmall
                                ?.copyWith(color: Couleurs.grisChaud)),
                      ),
                    if (page != null) ...[
                      const SizedBox(width: 8),
                      Text('p. $page',
                          style: t.textTheme.labelSmall
                              ?.copyWith(color: Couleurs.orTexte)),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${r['extrait'] ?? ''}',
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
