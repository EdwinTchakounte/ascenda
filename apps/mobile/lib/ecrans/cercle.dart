import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/cercle.dart';
import '../api/client.dart';
import '../etat/cercle.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../theme/texte.dart';
import '../widgets/etats.dart';

/// Le cercle de lecteurs : ses amis, ce qu'ils lisent, et de quoi se tenir
/// mutuellement au rythme.
///
/// On n'y cherche personne : on partage son code, on ajoute celui d'un ami.
/// C'est un cercle de gens qui se connaissent, pas un réseau public.
class EcranCercle extends ConsumerStatefulWidget {
  const EcranCercle({super.key});

  @override
  ConsumerState<EcranCercle> createState() => _EcranCercleState();
}

class _EcranCercleState extends ConsumerState<EcranCercle> {
  bool _vusEnvoyes = false;

  Future<void> _rafraichir() async {
    rafraichirCercle(ref);
    await ref.read(amisProvider.future).catchError((_) => <Ami>[]);
  }

  /// Les encouragements affichés sont marqués vus, une fois : la pastille de
  /// l'onglet retombe, mais la carte reste à l'écran jusqu'au prochain retour.
  void _marquerVus(List<EncouragementRecu> liste) {
    if (_vusEnvoyes || !liste.any((e) => e.nouveau)) return;
    _vusEnvoyes = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(clientApiProvider).post('/cercle/encouragements/vus');
        ref.invalidate(cercleMoiProvider);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final moi = ref.watch(cercleMoiProvider);
    final amis = ref.watch(amisProvider);
    final demandes = ref.watch(demandesProvider).valueOrNull ?? const Demandes();
    final fil = ref.watch(filProvider);
    final recus = ref.watch(encouragementsProvider).valueOrNull ?? const [];
    final nouveaux = recus.where((e) => e.nouveau).toList();
    _marquerVus(recus);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: moi.when(
          loading: () => const Padding(padding: EdgeInsets.all(20), child: SqueletteCarte(lignes: 5)),
          error: (e, _) => EtatErreur(erreur: e, reessayer: _rafraichir),
          data: (m) => RefreshIndicator(
            onRefresh: _rafraichir,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Texte('Mon cercle', style: t.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Texte(
                  "Lire à plusieurs tient mieux dans la durée. Suivez vos amis, "
                  "encouragez-les, écrivez-leur.",
                  style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
                ),
                const SizedBox(height: 18),
                _CarteCode(moi: m),

                if (demandes.recues.isNotEmpty) ...[
                  const _Titre('Demandes'),
                  for (final d in demandes.recues) _LigneDemande(demande: d),
                ],

                if (nouveaux.isNotEmpty) ...[
                  const _Titre('Pour vous'),
                  for (final e in nouveaux) _CarteEncouragement(encouragement: e),
                ],

                const _Titre('Fil de lecture'),
                fil.when(
                  loading: () => const SqueletteCarte(lignes: 3),
                  error: (e, _) => _Discret("Le fil n'a pas pu se charger. Tirez vers le bas pour réessayer."),
                  data: (evenements) => evenements.isEmpty
                      ? const _Discret(
                          "Rien encore ces quatorze derniers jours. Les séances et les quiz de vos amis "
                          "apparaîtront ici.")
                      : Column(children: [for (final e in evenements.take(20)) _LigneFil(evenement: e)]),
                ),

                const _Titre('Mes amis'),
                amis.when(
                  loading: () => const SqueletteCarte(lignes: 3),
                  error: (e, _) => EtatErreur(erreur: e, reessayer: _rafraichir),
                  data: (liste) => liste.isEmpty
                      ? const _Discret(
                          "Votre cercle est vide pour l'instant. Partagez votre code, ou ajoutez celui "
                          "d'un ami : l'amitié commence dès qu'il accepte.")
                      : Column(children: [for (final a in liste) _LigneAmi(ami: a)]),
                ),
                if (demandes.envoyees.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _Discret('En attente de réponse : ${demandes.envoyees.map((d) => d.lecteur.nom).join(', ')}.'),
                ],

                const _Titre('Confidentialité'),
                _Partage(actif: m.partageActivite),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10),
        child: Texte(texte, style: Theme.of(context).textTheme.titleLarge),
      );
}

class _Discret extends StatelessWidget {
  const _Discret(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Texte(
        texte,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud, height: 1.55),
      );
}

class Pastille extends StatelessWidget {
  const Pastille({super.key, required this.lecteur, this.taille = 42});
  final Lecteur lecteur;
  final double taille;

  @override
  Widget build(BuildContext context) {
    // Une teinte stable par lecteur, prise dans celles des pôles : un visage se
    // reconnaît à sa couleur avant son nom.
    final teintes = Couleurs.poles.values.toList();
    final teinte = teintes[lecteur.id.codeUnits.fold(0, (a, b) => a + b) % teintes.length];
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      color: teinte.withValues(alpha: 0.16),
      child: Texte(
        lecteur.initiale,
        style: TextStyle(color: teinte, fontWeight: FontWeight.w700, fontSize: taille * 0.42),
      ),
    );
  }
}

// ------------------------------------------------------------------ le code

class _CarteCode extends ConsumerWidget {
  const _CarteCode({required this.moi});
  final CercleMoi moi;

  Future<void> _inviter(BuildContext context) async {
    final lien = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(moi.messagePartage)}');
    if (!await launchUrl(lien, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: moi.messagePartage));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Texte("WhatsApp n'est pas disponible : le message est copié.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      color: Couleurs.nuit,
      child: Column(
        children: [
          Texte('Votre code ASCENDA',
              style: t.textTheme.labelLarge?.copyWith(color: const Color(0xFFB9C1D6), letterSpacing: 0.6)),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SelectableText(
              moi.code,
              key: const Key('code-cercle'),
              style: const TextStyle(
                color: Couleurs.orClair, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 4),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _inviter(context),
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Texte('Inviter'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Couleurs.orClair,
                    side: const BorderSide(color: Color(0x40E8C070)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _ajouter(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Texte('Ajouter'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _ajouter(BuildContext context, WidgetRef ref) async {
    final message = await showDialog<String>(context: context, builder: (_) => const _DialogueAjout());
    if (message != null && context.mounted) {
      rafraichirCercle(ref);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Texte(message)));
    }
  }
}

class _DialogueAjout extends ConsumerStatefulWidget {
  const _DialogueAjout();

  @override
  ConsumerState<_DialogueAjout> createState() => _DialogueAjoutState();
}

class _DialogueAjoutState extends ConsumerState<_DialogueAjout> {
  final _code = TextEditingController();
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (_code.text.trim().length < 3) {
      setState(() => _erreur = "Recopiez le code de votre ami, par exemple AWA-7KQ2.");
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final r = await ref.read(clientApiProvider).post('/cercle/amis', corps: {'code': _code.text.trim()})
          as Map<String, dynamic>;
      final nom = '${(r['ami'] as Map?)?['nom'] ?? 'Votre ami'}';
      if (!mounted) return;
      Navigator.of(context).pop(r['statut'] == 'acceptee'
          ? '$nom vous avait déjà ajouté : vous êtes maintenant amis.'
          : 'Demande envoyée à $nom. Elle attend sa réponse.');
    } on ErreurApi catch (e) {
      setState(() {
        _envoi = false;
        _erreur = e.message;
      });
    } catch (_) {
      setState(() {
        _envoi = false;
        _erreur = "La demande n'a pas pu partir. Vérifiez votre connexion.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Texte('Ajouter un ami'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Texte("Saisissez le code ASCENDA qu'il vous a transmis."),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: 'Code', hintText: 'AWA-7KQ2', errorText: _erreur, errorMaxLines: 3),
            onSubmitted: (_) => _envoyer(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Texte('Annuler')),
        FilledButton(onPressed: _envoi ? null : _envoyer, child: const Texte('Envoyer')),
      ],
    );
  }
}

// ---------------------------------------------------------------- les lignes

class _LigneDemande extends ConsumerWidget {
  const _LigneDemande({required this.demande});
  final DemandeAmi demande;

  Future<void> _repondre(BuildContext context, WidgetRef ref, bool accepter) async {
    try {
      final api = ref.read(clientApiProvider);
      accepter
          ? await api.post('/cercle/demandes/${demande.id}/accepter')
          : await api.post('/cercle/demandes/${demande.id}/refuser');
      rafraichirCercle(ref);
      if (context.mounted && accepter) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Texte('${demande.lecteur.nom} fait maintenant partie de votre cercle.')),
        );
      }
    } on ErreurApi catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Texte(e.message)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: Couleurs.ombreDouce),
      child: Row(
        children: [
          Pastille(lecteur: demande.lecteur),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte(demande.lecteur.nom, style: t.textTheme.titleSmall),
                Texte('veut rejoindre votre cercle',
                    style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refuser',
            onPressed: () => _repondre(context, ref, false),
            icon: const Icon(Icons.close_rounded, color: Couleurs.grisChaud),
          ),
          FilledButton(onPressed: () => _repondre(context, ref, true), child: const Texte('Accepter')),
        ],
      ),
    );
  }
}

class _CarteEncouragement extends StatelessWidget {
  const _CarteEncouragement({required this.encouragement});
  final EncouragementRecu encouragement;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = encouragement;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Couleurs.or.withValues(alpha: 0.09),
        border: const Border(left: BorderSide(color: Couleurs.or, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconeGenre(e.genre), color: Couleurs.orTexte, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte('« ${e.message} »', style: t.textTheme.bodyLarge?.copyWith(height: 1.45)),
                const SizedBox(height: 6),
                Texte(
                  [e.auteur.nom, if (e.ouvrage != null) e.ouvrage!, ilYA(e.le)].join(' · '),
                  style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData iconeGenre(String genre) => switch (genre) {
      'bravo' => Icons.celebration_outlined,
      'courage' => Icons.local_fire_department_outlined,
      'defi' => Icons.flag_outlined,
      'merci' => Icons.favorite_outline_rounded,
      'quiz' => Icons.quiz_outlined,
      'notion' => Icons.lightbulb_outline_rounded,
      _ => Icons.menu_book_outlined,
    };

class _LigneFil extends ConsumerWidget {
  const _LigneFil({required this.evenement});
  final EvenementFil evenement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final e = evenement;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pastille(lecteur: e.lecteur, taille: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: e.lecteur.nom, style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' ${lisible(e.texte)}'),
                  ]),
                  style: t.textTheme.bodyMedium,
                ),
                if (e.ouvrage != null)
                  Texte(e.ouvrage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: Couleurs.orTexte)),
                Texte(ilYA(e.le), style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          e.encourage
              ? const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.check_rounded, size: 20, color: Couleurs.sauge, semanticLabel: 'Encouragé'),
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 36),
                  ),
                  onPressed: () => encourager(context, ref, e.lecteur, evenement: e),
                  child: const Texte('Encourager'),
                ),
        ],
      ),
    );
  }
}

class _LigneAmi extends StatelessWidget {
  const _LigneAmi({required this.ami});
  final Ami ami;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final l = ami.lecture;
    final resume = !l.partage
        ? "ne partage pas son activité"
        : l.seancesSemaine == 0
            ? (l.derniereActivite != null ? 'dernière lecture ${ilYA(l.derniereActivite)}' : 'pas encore de séance')
            : '${l.seancesSemaine} séance${l.seancesSemaine > 1 ? 's' : ''} · ${l.minutesSemaine} min cette semaine';
    return InkWell(
      onTap: () => context.push('/cercle/ami/${ami.lecteur.id}?nom=${Uri.encodeComponent(ami.lecteur.nom)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Pastille(lecteur: ami.lecteur),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Texte(ami.lecteur.nom, style: t.textTheme.titleSmall),
                  Texte(resume, style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
                  if (l.partage && l.lit != null)
                    Texte('lit ${l.lit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(color: Couleurs.orTexte)),
                ],
              ),
            ),
            if (ami.nonLus > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                color: Couleurs.or,
                child: Texte('${ami.nonLus}',
                    style: t.textTheme.labelSmall?.copyWith(color: Couleurs.nuitProfond, fontWeight: FontWeight.w700)),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: Couleurs.grisChaud),
          ],
        ),
      ),
    );
  }
}

class _Partage extends ConsumerStatefulWidget {
  const _Partage({required this.actif});
  final bool actif;

  @override
  ConsumerState<_Partage> createState() => _PartageState();
}

class _PartageState extends ConsumerState<_Partage> {
  late bool _actif = widget.actif;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _actif,
      title: const Texte('Montrer ma lecture à mes amis'),
      subtitle: const Texte(
        "Vos séances et vos quiz apparaissent dans leur fil. Vos notes, vos réponses et "
        "vos échanges restent privés dans tous les cas.",
      ),
      onChanged: (v) async {
        setState(() => _actif = v);
        try {
          await ref.read(clientApiProvider).patch('/cercle/preferences', corps: {'partage_activite': v});
        } catch (_) {
          if (mounted) setState(() => _actif = !v);
        }
      },
    );
  }
}

// ------------------------------------------------------------ encourager

/// Ouvre le choix d'un encouragement. Trois messages prêts, et la place d'un
/// mot à soi : encourager doit prendre deux secondes, pas une rédaction.
Future<void> encourager(BuildContext context, WidgetRef ref, Lecteur ami, {EvenementFil? evenement}) async {
  final envoye = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FeuilleEncouragement(ami: ami, evenement: evenement),
  );
  if (envoye == true && context.mounted) {
    ref.invalidate(filProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Texte('Encouragement envoyé à ${ami.nom}.')),
    );
  }
}

class _FeuilleEncouragement extends ConsumerStatefulWidget {
  const _FeuilleEncouragement({required this.ami, this.evenement});
  final Lecteur ami;
  final EvenementFil? evenement;

  @override
  ConsumerState<_FeuilleEncouragement> createState() => _FeuilleEncouragementState();
}

class _FeuilleEncouragementState extends ConsumerState<_FeuilleEncouragement> {
  static const _genres = [
    ('bravo', 'Bravo pour ta lecture !'),
    ('courage', 'Courage, tu tiens le bon rythme.'),
    ('defi', 'On lit la même chose cette semaine ?'),
  ];
  String _genre = 'bravo';
  final _mot = TextEditingController();
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _mot.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await ref.read(clientApiProvider).post('/cercle/encouragements', corps: {
        'ami_id': widget.ami.id,
        'genre': _genre,
        if (_mot.text.trim().isNotEmpty) 'message': _mot.text.trim(),
        if (widget.evenement != null) 'evenement_id': widget.evenement!.id,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ErreurApi catch (e) {
      setState(() {
        _envoi = false;
        _erreur = e.message;
      });
    } catch (_) {
      setState(() {
        _envoi = false;
        _erreur = "L'encouragement n'a pas pu partir. Vérifiez votre connexion.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Texte('Encourager ${widget.ami.nom}', style: t.textTheme.titleLarge),
            if (widget.evenement != null) ...[
              const SizedBox(height: 4),
              Texte('${widget.ami.nom} ${widget.evenement!.texte}',
                  style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
            ],
            const SizedBox(height: 14),
            RadioGroup<String>(
              groupValue: _genre,
              onChanged: (v) => setState(() => _genre = v ?? _genre),
              child: Column(
                children: [
                  for (final (cle, libelle) in _genres)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: cle,
                      title: Texte(libelle),
                      secondary: Icon(iconeGenre(cle), color: Couleurs.orTexte),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _mot,
              maxLength: 280,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Un mot à vous (facultatif)', errorText: _erreur),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _envoi ? null : _envoyer, child: const Texte('Envoyer')),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- la conversation

class EcranConversation extends ConsumerStatefulWidget {
  const EcranConversation({super.key, required this.amiId, this.nom});

  final String amiId;
  final String? nom;

  @override
  ConsumerState<EcranConversation> createState() => _EcranConversationState();
}

class _EcranConversationState extends ConsumerState<EcranConversation> {
  final _saisie = TextEditingController();
  Timer? _sondage;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _marquerLus();
    // Une conversation ouverte se tient à jour toute seule. Dix secondes : assez
    // vif pour un échange, assez sobre pour un forfait mobile.
    _sondage = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(conversationProvider(widget.amiId));
      _marquerLus();
    });
  }

  @override
  void dispose() {
    _sondage?.cancel();
    _saisie.dispose();
    super.dispose();
  }

  Future<void> _marquerLus() async {
    try {
      final r = await ref.read(clientApiProvider).post('/cercle/echanges/${widget.amiId}/lus') as Map?;
      if ((r?['marques'] as int? ?? 0) > 0 && mounted) {
        ref
          ..invalidate(amisProvider)
          ..invalidate(cercleMoiProvider);
      }
    } catch (_) {}
  }

  Future<void> _envoyer() async {
    final texte = _saisie.text.trim();
    if (texte.isEmpty || _envoi) return;
    setState(() => _envoi = true);
    try {
      await ref.read(clientApiProvider).post('/cercle/echanges/${widget.amiId}', corps: {'texte': texte});
      _saisie.clear();
      ref.invalidate(conversationProvider(widget.amiId));
    } on ErreurApi catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Texte(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Texte("Le message n'est pas parti. Vérifiez votre connexion.")),
        );
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _signaler(Echange m) async {
    final motif = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Texte('Signaler ce message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Texte("La modération le lira, lui seul, et pourra le retirer. Votre ami n'en est pas averti."),
            const SizedBox(height: 12),
            TextField(controller: motif, maxLength: 500, decoration: const InputDecoration(labelText: 'Pourquoi ?')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Texte('Annuler')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Texte('Signaler')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(clientApiProvider).post('/cercle/signalements',
          corps: {'echange_id': m.id, 'motif': motif.text.trim().length >= 3 ? motif.text.trim() : 'Signalé'});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Texte('Merci. Le message est transmis à la modération.')));
      }
    } on ErreurApi catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Texte(e.message)));
    }
  }

  Future<void> _menu(String choix, Lecteur ami) async {
    if (choix == 'encourager') {
      await encourager(context, ref, ami);
      return;
    }
    final bloquer = choix == 'bloquer';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Texte(bloquer ? 'Bloquer ${ami.nom} ?' : 'Retirer ${ami.nom} de votre cercle ?'),
        content: Texte(bloquer
            ? "Vous ne serez plus amis, et ${ami.nom} ne pourra plus vous écrire ni vous redemander. "
                "Rien ne lui est notifié."
            : "Vous ne verrez plus sa lecture et ne pourrez plus vous écrire. Vous pourrez vous réajouter "
                "plus tard."),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Texte('Annuler')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: Texte(bloquer ? 'Bloquer' : 'Retirer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final api = ref.read(clientApiProvider);
      bloquer ? await api.post('/cercle/bloquer/${ami.id}') : await api.delete('/cercle/amis/${ami.id}');
      rafraichirCercle(ref);
      if (mounted) context.pop();
    } on ErreurApi catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Texte(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final conv = ref.watch(conversationProvider(widget.amiId));
    final ami = conv.valueOrNull?.ami ?? Lecteur(id: widget.amiId, nom: widget.nom ?? 'Conversation');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Pastille(lecteur: ami, taille: 32),
            const SizedBox(width: 10),
            Flexible(child: Texte(ami.nom, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (c) => _menu(c, ami),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'encourager', child: Texte('Encourager')),
              PopupMenuItem(value: 'retirer', child: Texte('Retirer du cercle')),
              PopupMenuItem(value: 'bloquer', child: Texte('Bloquer')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: conv.when(
                skipLoadingOnRefresh: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => EtatErreur(
                    erreur: e, reessayer: () => ref.invalidate(conversationProvider(widget.amiId))),
                data: (c) => c.messages.isEmpty
                    ? EtatMessage(
                        icone: Icons.forum_outlined,
                        titre: 'Écrivez à ${c.ami.nom}',
                        texte: "Où en êtes-vous de vos lectures ? Une question sur un chapitre, un livre "
                            "à conseiller : c'est l'endroit.",
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        itemCount: c.messages.length,
                        itemBuilder: (_, i) {
                          final m = c.messages[c.messages.length - 1 - i];
                          return _Bulle(message: m, onSignaler: m.deMoi ? null : () => _signaler(m));
                        },
                      ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Couleurs.traitClair)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _saisie,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Votre message',
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: _envoi ? null : _envoyer,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    style: IconButton.styleFrom(backgroundColor: Couleurs.or, foregroundColor: Couleurs.nuitProfond),
                  ),
                ],
              ),
            ),
            if (conv.hasValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Texte('Appui long sur un message reçu pour le signaler.',
                    style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message, this.onSignaler});
  final Echange message;
  final VoidCallback? onSignaler;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final m = message;
    return Align(
      alignment: m.deMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onSignaler,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: m.deMoi ? Couleurs.nuit : Colors.white,
            boxShadow: m.deMoi ? null : Couleurs.ombreDouce,
          ),
          child: Column(
            crossAxisAlignment: m.deMoi ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Texte(m.texte,
                  textAlign: TextAlign.start,
                  style: t.textTheme.bodyMedium?.copyWith(
                      color: m.deMoi ? const Color(0xFFF7F4EC) : Couleurs.encreDouce, height: 1.45)),
              const SizedBox(height: 4),
              Texte(
                [ilYA(m.le), if (m.deMoi && m.lu) 'lu'].join(' · '),
                style: t.textTheme.labelSmall
                    ?.copyWith(color: m.deMoi ? const Color(0xFF9AA3B8) : Couleurs.grisChaud),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
