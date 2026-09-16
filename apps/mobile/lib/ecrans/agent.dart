import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/palette.dart';
import '../theme/texte.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';

/// La conversation avec l'agent.
///
/// Chaque réponse porte ses citations sous forme de cartes cliquables
/// « Ouvrage, p. 47 ». C'est la règle du produit : on ne répond jamais sans
/// dire d'où vient la réponse.
class PanneauAgent extends ConsumerStatefulWidget {
  const PanneauAgent({
    super.key,
    this.documentId,
    this.chapitreId,
    this.axe,
    this.conversationId,
    this.avant,
    this.actions = const [],
  });

  /// Dans l'onglet, le panneau tient lieu de barre du haut : il porte le bouton
  /// du tiroir et les actions, au lieu d'empiler un titre « Agent » au-dessus
  /// de son propre en-tête « L'agent ».
  final Widget? avant;
  final List<Widget> actions;

  final String? documentId;
  final String? chapitreId;
  final String? axe;

  /// Une conversation passée à rouvrir. Nulle, on en commence une nouvelle.
  final String? conversationId;

  @override
  ConsumerState<PanneauAgent> createState() => _PanneauAgentState();
}

class _PanneauAgentState extends ConsumerState<PanneauAgent> {
  final _saisie = TextEditingController();
  final _defilement = ScrollController();
  final List<MessageAgent> _messages = [];

  String? _conversationId;
  List<String> _suggestions = [];
  bool _attente = false;
  int? _restant;

  @override
  void initState() {
    super.initState();
    if (widget.conversationId != null) {
      _conversationId = widget.conversationId;
      _rouvrir(widget.conversationId!);
    } else {
      _chargerSuggestions();
    }
  }

  /// Recharge les messages d'une conversation passée.
  ///
  /// La liste des conversations existait déjà, mais on ne pouvait rien en
  /// faire : les rouvrir était la seule chose qu'un lecteur cherche à faire
  /// avec un historique.
  Future<void> _rouvrir(String id) async {
    setState(() => _attente = true);
    try {
      final j = await ref.read(clientApiProvider).get('/agent/conversations/$id')
          as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(((j['messages'] as List?) ?? [])
              .map((m) => MessageAgent.depuisJson(m as Map<String, dynamic>)));
        _suggestions = const [];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Texte("Cette conversation n'a pas pu être rouverte.")),
      );
    } finally {
      if (mounted) setState(() => _attente = false);
    }
  }

  @override
  void dispose() {
    _saisie.dispose();
    _defilement.dispose();
    super.dispose();
  }

  Future<void> _chargerSuggestions() async {
    try {
      final j = await ref.read(clientApiProvider).get('/agent/suggestions', params: {
        'document_id': ?widget.documentId,
        'chapitre_id': ?widget.chapitreId,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _suggestions = (j['suggestions'] as List).map((e) => '$e').toList());
    } catch (_) {
      // Sans suggestions l'écran reste utilisable : on n'affiche rien.
    }
  }

  Future<void> _envoyer([String? texte]) async {
    final question = (texte ?? _saisie.text).trim();
    if (question.isEmpty || _attente) return;

    setState(() {
      _messages.add(MessageAgent(role: 'user', texte: question));
      _attente = true;
      _saisie.clear();
      _suggestions = [];
    });
    _versLeBas();

    try {
      final j = await ref.read(clientApiProvider).post('/agent/questions', corps: {
        'question': question,
        'conversation_id': ?_conversationId,
        'document_id': ?widget.documentId,
        'axe': ?widget.axe,
      }) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _conversationId = '${j['conversation_id']}';
        _restant = (j['quota'] as Map?)?['restant'] as int?;
        _messages.add(MessageAgent.depuisJson(j));
        _attente = false;
      });
      _versLeBas();
    } on ErreurApi catch (e) {
      if (!mounted) return;
      setState(() {
        _attente = false;
        _messages.add(MessageAgent(role: 'assistant', texte: e.message, degrade: true));
      });
      _versLeBas();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _attente = false;
        _messages.add(const MessageAgent(
          role: 'assistant',
          texte: "Je n'ai pas pu répondre. Vérifiez votre connexion et réessayez.",
          degrade: true,
        ));
      });
    }
  }

  void _versLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_defilement.hasClients) return;
      _defilement.animateTo(
        _defilement.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final clavier = MediaQuery.of(context).viewInsets.bottom > 0;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(widget.avant == null ? 20 : 4, 14, 12, 10),
          child: Row(
            children: [
              if (widget.avant != null) ...[widget.avant!, const SizedBox(width: 2)],
              const _AvatarAgent(taille: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte("L'agent", style: t.textTheme.titleLarge?.copyWith(fontSize: 19)),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _restant == 0 ? p.alerte : p.succes,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Texte(
                            _restant == null
                                ? 'Il répond en citant le livre et la page.'
                                : '$_restant question${_restant! > 1 ? 's' : ''} restante'
                                    '${_restant! > 1 ? 's' : ''} aujourd\'hui',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (Navigator.canPop(context))
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ...widget.actions,
            ],
          ),
        ),
        Divider(height: 1, color: p.trait),
        Expanded(
          child: _messages.isEmpty
              ? _Accueil(suggestions: _suggestions, onChoisi: _envoyer)
              : ListView.builder(
                  controller: _defilement,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                  itemCount: _messages.length + (_attente ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _messages.length) return const _Reflexion();
                    return _Bulle(message: _messages[i]);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, clavier ? 8 : 14),
            child: ZoneMessage(
              controleur: _saisie,
              attente: _attente,
              indication: 'Posez votre question…',
              envoiAuClavier: true,
              onEnvoyer: () => _envoyer(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Le visage de l'agent : une étincelle dorée dans un disque.
class _AvatarAgent extends StatelessWidget {
  const _AvatarAgent({this.taille = 30});
  final double taille;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: p.degradeHeros,
        boxShadow: [BoxShadow(color: p.heros.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: Icon(Icons.auto_awesome_rounded, size: taille * 0.5, color: p.accentSurHeros),
    );
  }
}

class _Accueil extends StatelessWidget {
  const _Accueil({required this.suggestions, required this.onChoisi});
  final List<String> suggestions;
  final void Function(String) onChoisi;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        SurfaceHeros(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconePastille(Icons.auto_stories_rounded, couleur: p.accentSurHeros, taille: 48),
              const SizedBox(height: 16),
              Surtitre('Agent de lecture', couleur: p.accentSurHeros),
              const SizedBox(height: 6),
              Texte(
                'Demandez ce que vous voulez',
                style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 24),
              ),
              const SizedBox(height: 10),
              Texte(
                "L'agent ne répond que sur les ouvrages du corpus, et il indique "
                "toujours d'où vient sa réponse. S'il ne trouve rien, il le dit.",
                style: t.textTheme.bodyMedium?.copyWith(color: p.surHerosDoux),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pastille('Livre et page cités', icone: Icons.format_quote_rounded, couleur: p.accentSurHeros),
                  Pastille('Corpus seulement', icone: Icons.verified_outlined, couleur: p.surHeros),
                ],
              ),
            ],
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 26),
          const TitreSection('Pour commencer', sousTitre: 'Touchez une question pour la poser.'),
          const SizedBox(height: 12),
          for (final s in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                onTap: () => onChoisi(s),
                child: Row(
                  children: [
                    const IconePastille(Icons.lightbulb_outline_rounded, taille: 38),
                    const SizedBox(width: 13),
                    Expanded(child: Texte(s, style: t.textTheme.bodyMedium?.copyWith(color: p.encre))),
                    const SizedBox(width: 8),
                    Icon(Icons.north_east_rounded, size: 17, color: p.accentTexte),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message});
  final MessageAgent message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final utilisateur = message.deLUtilisateur;
    final largeurMax = MediaQuery.of(context).size.width * (utilisateur ? 0.8 : 0.76);

    final bulle = Container(
      constraints: BoxConstraints(maxWidth: largeurMax),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: utilisateur
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.accentSurHeros, p.accent],
              )
            : null,
        color: utilisateur ? null : p.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(utilisateur ? 22 : 6),
          bottomRight: Radius.circular(utilisateur ? 6 : 22),
        ),
        border: utilisateur ? null : Border.all(color: p.trait),
        boxShadow: utilisateur
            ? [BoxShadow(color: p.accent.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 5))]
            : p.ombreCarte,
      ),
      child: SelectableText(
        message.texte,
        style: t.textTheme.bodyMedium?.copyWith(
          height: 1.62,
          color: utilisateur ? p.surAccent : p.texte,
        ),
      ),
    );

    if (utilisateur) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16, left: 40),
        child: Align(alignment: Alignment.centerRight, child: bulle),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: _AvatarAgent()),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bulle,
                if (message.citations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.format_quote_rounded, size: 15, color: p.accentTexte),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Surtitre(
                            message.citations.length > 1
                                ? '${message.citations.length} sources'
                                : '1 source',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 118,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: message.citations.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => _CarteCitation(citation: message.citations[i]),
                    ),
                  ),
                ],
                if (message.degrade)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.info_outline_rounded, size: 14, color: p.attenue),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Texte(
                            'Réponse limitée : la rédaction automatique est indisponible.',
                            style: t.textTheme.labelSmall?.copyWith(color: p.attenue),
                          ),
                        ),
                      ],
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

class _CarteCitation extends StatelessWidget {
  const _CarteCitation({required this.citation});
  final Citation citation;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return SizedBox(
      width: 232,
      child: Surface(
        ombre: false,
        rayon: const BorderRadius.all(Radius.circular(18)),
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
        onTap: citation.documentId == null
            ? null
            : () => context.push('/ouvrage/${citation.documentId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.accentVoile, shape: BoxShape.circle),
                  child: citation.marque != null
                      ? Texte('${citation.marque}',
                          style: t.textTheme.labelSmall
                              ?.copyWith(color: p.accentTexte, fontWeight: FontWeight.w700, letterSpacing: 0))
                      : Icon(Icons.menu_book_rounded, size: 12, color: p.accentTexte),
                ),
                Expanded(
                  child: Texte(
                    citation.ouvrage,
                    style: t.textTheme.labelMedium?.copyWith(color: p.encre, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Expanded(
              child: Texte(
                citation.extrait,
                style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (citation.page != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: p.accentVoile, borderRadius: Rayons.pilule),
                child: Texte('p. ${citation.page}',
                    style: t.textTheme.labelSmall?.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}

/// L'agent réfléchit : trois points qui respirent dans une bulle.
class _Reflexion extends StatefulWidget {
  const _Reflexion();

  @override
  State<_Reflexion> createState() => _ReflexionState();
}

class _ReflexionState extends State<_Reflexion> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: _AvatarAgent()),
          const SizedBox(width: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomRight: Radius.circular(22),
                bottomLeft: Radius.circular(6),
              ),
              border: Border.all(color: p.trait),
              boxShadow: p.ombreCarte,
            ),
            child: Semantics(
              label: "L'agent réfléchit",
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Builder(builder: (context) {
                        // Chaque point s'allume à son tour, décalé d'un tiers de cycle.
                        final phase = (_c.value - i / 3) % 1;
                        final eclat = phase < 0.5 ? 1 - (phase - 0.25).abs() * 4 : 0.0;
                        final v = eclat.clamp(0.0, 1.0);
                        return Transform.translate(
                          offset: Offset(0, -3 * v),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color.lerp(p.attenue.withValues(alpha: 0.4), p.accentTexte, v),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// L'onglet Agent : la conversation en plein écran, et l'accès aux précédentes.
class EcranAgent extends ConsumerStatefulWidget {
  const EcranAgent({super.key});

  @override
  ConsumerState<EcranAgent> createState() => _EcranAgentState();
}

class _EcranAgentState extends ConsumerState<EcranAgent> {
  /// Change quand on rouvre une conversation : la clé force la reconstruction
  /// du panneau, sans quoi les messages de la précédente resteraient à l'écran.
  String? _conversation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PanneauAgent(
          key: ValueKey(_conversation ?? 'nouvelle'),
          conversationId: _conversation,
          avant: const BoutonMenu(),
          actions: [
            if (_conversation != null)
              IconButton(
                tooltip: 'Nouvelle conversation',
                icon: const Icon(Icons.add_comment_outlined, size: 21),
                onPressed: () => setState(() => _conversation = null),
              ),
            IconButton(
              tooltip: 'Conversations précédentes',
              icon: const Icon(Icons.history_rounded, size: 22),
              onPressed: _ouvrirHistorique,
            ),
          ],
        ),
      ),
    );
  }

  void _ouvrirHistorique() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.palette.fond,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.8,
        child: _Historique(
          onOuvrir: (id) {
            Navigator.pop(context);
            setState(() => _conversation = id);
          },
        ),
      ),
    );
  }
}

/// La liste des conversations passées, avec de quoi en effacer une.
class _Historique extends ConsumerWidget {
  const _Historique({required this.onOuvrir});

  final void Function(String) onOuvrir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final conversations = ref.watch(conversationsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Row(
            children: [
              const IconePastille(Icons.history_rounded, taille: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte('Vos conversations', style: t.textTheme.headlineSmall?.copyWith(fontSize: 22)),
                    Texte(
                      'Touchez un échange pour le reprendre.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: conversations.when(
            loading: () => ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, _) => const SqueletteCarte(lignes: 1),
            ),
            error: (e, _) => EtatErreur(
              erreur: e,
              reessayer: () => ref.invalidate(conversationsProvider),
            ),
            data: (liste) => liste.isEmpty
                ? const EtatMessage(
                    icone: Icons.forum_outlined,
                    titre: 'Aucune conversation',
                    texte: "Vos échanges avec l'agent s'accumuleront ici, avec leurs "
                        "sources, pour que vous puissiez y revenir.",
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                    itemCount: liste.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = liste[i];
                      final n = c['nb_messages'];
                      return Surface(
                        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                        onTap: () => onOuvrir('${c['id']}'),
                        child: Row(
                          children: [
                            const IconePastille(Icons.chat_bubble_outline_rounded, taille: 40),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Texte('${c['titre'] ?? 'Sans titre'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.textTheme.titleSmall),
                                  if (n != null) ...[
                                    const SizedBox(height: 3),
                                    Texte('$n message${(n as int) > 1 ? 's' : ''}',
                                        style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 20),
                              color: p.attenue,
                              tooltip: 'Supprimer',
                              onPressed: () => _supprimer(context, ref, '${c['id']}'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _supprimer(BuildContext context, WidgetRef ref, String id) async {
    final oui = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.delete_outline_rounded, color: context.palette.alerte),
        content: const Texte('Supprimer cette conversation ?', textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Texte('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Texte('Supprimer')),
        ],
      ),
    );
    if (oui != true) return;
    try {
      await ref.read(clientApiProvider).delete('/agent/conversations/$id');
      ref.invalidate(conversationsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Texte("La conversation n'a pas pu être supprimée.")),
        );
      }
    }
  }
}
