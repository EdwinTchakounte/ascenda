import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

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
    final p = context.palette;
    final assez = _requete.length >= 3;
    final resultats = ref.watch(rechercheProvider(_requete));
    final suggestions = ref.watch(suggestionsProvider(_requete));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 64,
        // Le champ en pilule creusée dans la barre : l'écran entier est une
        // question, elle mérite d'être le premier objet visible.
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _champ,
            autofocus: widget.initiale == null,
            onChanged: _saisie,
            onSubmitted: (v) => setState(() => _requete = v.trim()),
            textInputAction: TextInputAction.search,
            style: t.textTheme.bodyLarge?.copyWith(color: p.encre, height: 1.3),
            decoration: InputDecoration(
              hintText: 'Une idée, une question, un nom…',
              filled: true,
              fillColor: p.surfaceCreuse,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              prefixIcon: Icon(Icons.search_rounded, size: 21, color: p.attenue),
              border: const OutlineInputBorder(borderRadius: Rayons.pilule, borderSide: BorderSide.none),
              enabledBorder: const OutlineInputBorder(borderRadius: Rayons.pilule, borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: Rayons.pilule,
                borderSide: BorderSide(color: p.accentTexte.withValues(alpha: 0.6), width: 1.4),
              ),
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
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
                    children: [
                      if (ouvrages.isNotEmpty) ...[
                        const TitreSection('Ouvrages'),
                        const SizedBox(height: 12),
                        for (final o in ouvrages.take(4)) ...[
                          _LigneOuvrage(ouvrage: o),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 18),
                      ],
                      if (liste.isNotEmpty) ...[
                        Row(
                          children: [
                            const Expanded(child: TitreSection('Dans le texte')),
                            const SizedBox(width: 8),
                            _Mode(mode: '${d['mode'] ?? ''}'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final r in liste) ...[
                          _CarteResultat(resultat: r),
                          const SizedBox(height: 12),
                        ],
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
    return Pastille(
      libelle,
      icone: mode == 'plein_texte' ? Icons.text_fields_rounded : Icons.auto_awesome_outlined,
      couleur: context.palette.attenue,
    );
  }
}

class _LigneOuvrage extends StatelessWidget {
  const _LigneOuvrage({required this.ouvrage});
  final Map<String, dynamic> ouvrage;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final auteurs = ((ouvrage['auteurs'] as List?) ?? []).join(', ');
    return Surface(
      onTap: () => context.push('/ouvrage/${ouvrage['id']}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const IconePastille(Icons.menu_book_rounded, taille: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte('${ouvrage['titre']}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                if (auteurs.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Texte(auteurs,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 22, color: p.attenue),
        ],
      ),
    );
  }
}

class _CarteResultat extends StatelessWidget {
  const _CarteResultat({required this.resultat});
  final Map<String, dynamic> resultat;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final r = resultat;
    final page = r['page'];
    final chapitreId = r['chapitre_id'];
    final documentId = '${r['document_id']}';

    return Surface(
      // Sans chapitre identifié, on ouvre la fiche de l'ouvrage : mieux
      // vaut arriver sur le livre que sur un écran vide.
      onTap: () => context.push(chapitreId == null
          ? '/ouvrage/$documentId'
          : '/lecture/$documentId/$chapitreId'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Texte('${r['ouvrage'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleMedium),
              ),
              if (page != null) ...[
                const SizedBox(width: 10),
                Pastille('p. $page'),
              ],
            ],
          ),
          if ('${r['chapitre'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 3),
            Texte('${r['chapitre']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelSmall?.copyWith(color: p.attenue)),
          ],
          const SizedBox(height: 12),
          // L'extrait sur un aplat en retrait, en Fraunces : c'est la voix du
          // livre, distincte des libellés de l'application.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(color: p.surfaceCreuse, borderRadius: Rayons.moyen),
            child: Texte(
              '${r['extrait'] ?? ''}',
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodySmall?.copyWith(
                fontFamily: t.textTheme.headlineSmall?.fontFamily,
                fontSize: 13.5,
                color: p.texte,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
