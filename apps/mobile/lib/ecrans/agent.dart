import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';
import '../theme/texte.dart';

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
  });

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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte("L'agent", style: t.textTheme.titleLarge),
                    Texte(
                      _restant == null
                          ? 'Il répond en citant le livre et la page.'
                          : '$_restant question${_restant! > 1 ? 's' : ''} restante'
                              '${_restant! > 1 ? 's' : ''} aujourd\'hui',
                      style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                    ),
                  ],
                ),
              ),
              if (Navigator.canPop(context))
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _messages.isEmpty
              ? _Accueil(suggestions: _suggestions, onChoisi: _envoyer)
              : ListView.builder(
                  controller: _defilement,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
            padding: EdgeInsets.fromLTRB(
              16, 8, 16, MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _saisie,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _envoyer(),
                    decoration: const InputDecoration(hintText: 'Posez votre question…'),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: Couleurs.or,
                  shape: const RoundedRectangleBorder(),
                  child: InkWell(
                    customBorder: const RoundedRectangleBorder(),
                    onTap: _attente ? null : () => _envoyer(),
                    child: const SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(Icons.arrow_upward_rounded, color: Color(0xFF1A1400)),
                    ),
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

class _Accueil extends StatelessWidget {
  const _Accueil({required this.suggestions, required this.onChoisi});
  final List<String> suggestions;
  final void Function(String) onChoisi;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      children: [
        const Icon(Icons.auto_stories_outlined, size: 34, color: Couleurs.orTexte),
        const SizedBox(height: 16),
        Texte('Demandez ce que vous voulez', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        Texte(
          "L'agent ne répond que sur les ouvrages du corpus, et il indique "
          "toujours d'où vient sa réponse. S'il ne trouve rien, il le dit.",
          style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
        ),
        const SizedBox(height: 26),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: InkWell(
              onTap: () => onChoisi(s),
              borderRadius: BorderRadius.zero,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: t.colorScheme.surface,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
                ),
                child: Row(
                  children: [
                    Expanded(child: Texte(s, style: t.textTheme.bodyMedium)),
                    const Icon(Icons.north_east_rounded, size: 16, color: Couleurs.grisChaud),
                  ],
                ),
              ),
            ),
          ),
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
    final utilisateur = message.deLUtilisateur;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment:
            utilisateur ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.84,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: utilisateur
                  ? Couleurs.or.withValues(alpha: 0.14)
                  : t.colorScheme.surface,
              borderRadius: BorderRadius.zero,
              border: utilisateur
                  ? null
                  : Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
            ),
            child: SelectableText(
              message.texte,
              style: t.textTheme.bodyMedium?.copyWith(height: 1.62),
            ),
          ),
          if (message.citations.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: message.citations.length,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (context, i) => _CarteCitation(citation: message.citations[i]),
              ),
            ),
          ],
          if (message.degrade && !utilisateur)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Texte(
                'Réponse limitée : la rédaction automatique est indisponible.',
                style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud),
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
    return InkWell(
      onTap: citation.documentId == null
          ? null
          : () => context.push('/ouvrage/${citation.documentId}'),
      borderRadius: BorderRadius.zero,
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: t.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.zero,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (citation.marque != null)
                  Container(
                    margin: const EdgeInsets.only(right: 7),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Couleurs.or.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Texte('${citation.marque}',
                        style: t.textTheme.labelSmall
                            ?.copyWith(color: Couleurs.orTexte, fontWeight: FontWeight.w700)),
                  ),
                Expanded(
                  child: Texte(
                    citation.ouvrage,
                    style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Texte(
                citation.extrait,
                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (citation.page != null)
              Texte('p. ${citation.page}',
                  style: t.textTheme.labelSmall?.copyWith(color: Couleurs.orTexte)),
          ],
        ),
      ),
    );
  }
}

class _Reflexion extends StatelessWidget {
  const _Reflexion();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.zero,
            ),
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
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
      appBar: AppBar(
        title: const Texte('Agent'),
        actions: [
          if (_conversation != null)
            IconButton(
              tooltip: 'Nouvelle conversation',
              icon: const Icon(Icons.add_comment_outlined, size: 21),
              onPressed: () => setState(() => _conversation = null),
            ),
          IconButton(
            tooltip: 'Conversations précédentes',
            icon: const Icon(Icons.history_rounded, size: 21),
            onPressed: _ouvrirHistorique,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: PanneauAgent(
          key: ValueKey(_conversation ?? 'nouvelle'),
          conversationId: _conversation,
        ),
      ),
    );
  }

  void _ouvrirHistorique() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
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
    final conversations = ref.watch(conversationsProvider);
    return Column(
      children: [
        const SizedBox(height: 14),
        Texte('Vos conversations', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        Expanded(
          child: conversations.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
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
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: liste.length,
                    itemBuilder: (_, i) {
                      final c = liste[i];
                      final n = c['nb_messages'];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                        title: Texte('${c['titre'] ?? 'Sans titre'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodyMedium),
                        subtitle: n == null
                            ? null
                            : Texte('$n message${(n as int) > 1 ? 's' : ''}',
                                style: t.textTheme.bodySmall
                                    ?.copyWith(color: Couleurs.grisChaud)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 19),
                          color: Couleurs.grisChaud,
                          tooltip: 'Supprimer',
                          onPressed: () => _supprimer(context, ref, '${c['id']}'),
                        ),
                        onTap: () => onOuvrir('${c['id']}'),
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
        content: const Texte('Supprimer cette conversation ?'),
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
