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
import '../widgets/livre.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

class EcranRecherche extends ConsumerStatefulWidget {
  const EcranRecherche({super.key, this.initiale});

  final String? initiale;

  @override
  ConsumerState<EcranRecherche> createState() => _EtatRecherche();
}

class _EtatRecherche extends ConsumerState<EcranRecherche> {
  late final TextEditingController _champ =
      TextEditingController(text: widget.initiale ?? '');

  String _requete = '';
  Timer? _attente;

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
              prefixIcon: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
                child: IconeAscenda(Icone.loupe, taille: 19, couleur: p.attenue),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
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
      body: FondPapier(
        child: SafeArea(
          bottom: false,
          child: !assez
              ? const EtatMessage(
                  scene: Scene.loupeVide,
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
                        scene: Scene.loupeVide,
                        titre: 'Rien trouvé',
                        texte: "Aucun passage du corpus ne correspond. Essayez d'autres "
                            "mots, ou une formulation plus large.",
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
                      children: [
                        if (ouvrages.isNotEmpty) ...[
                          TitreCourant(
                            'ouvrages',
                            folio: ouvrages.length > 1 ? '${ouvrages.length} titres' : '1 titre',
                          ),
                          const SizedBox(height: 14),
                          for (final (i, o) in ouvrages.take(4).indexed) ...[
                            Apparition(rang: i, child: _LigneOuvrage(ouvrage: o)),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                        ],
                        if (liste.isNotEmpty) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TitreCourant(
                                  'dans le texte',
                                  folio: liste.length > 1 ? '${liste.length} passages' : '1 passage',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: _Mode(mode: '${d['mode'] ?? ''}'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          for (final (i, r) in liste.indexed) ...[
                            Apparition(rang: i, child: _CarteResultat(resultat: r)),
                            const SizedBox(height: 12),
                          ],
                        ],
                        const SizedBox(height: 20),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DosLivre(titre: '${ouvrage['titre']}', axeSlug: ouvrage['axe_slug'] as String?, hauteur: 74, largeur: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte('${ouvrage['titre']}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                if (auteurs.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Texte(auteurs,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconeAscenda(Icone.fleche, taille: 19, couleur: p.attenue),
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
      onTap: () => context.push(chapitreId == null
          ? '/ouvrage/$documentId'
          : '/lecture/$documentId/$chapitreId'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Texte('${r['ouvrage'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.titleMedium),
          const SizedBox(height: 6),
          TitreCourant(
            '${r['chapitre'] ?? ''}'.isNotEmpty ? '${r['chapitre']}' : 'dans le texte',
            folio: page != null ? '\u00A0\u00A0p. $page' : null,
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 2, color: p.accentTexte.withValues(alpha: 0.55)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 2, 2),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
