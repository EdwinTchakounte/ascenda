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
import '../theme/icones.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import '../widgets/etats.dart';
import '../widgets/illustrations.dart';
import '../widgets/ui.dart' hide Pastille;

/// Le cercle de lecteurs : ses amis, ce qu'ils lisent, et de quoi se tenir
/// mutuellement au rythme.
///
/// On n'y cherche personne : on partage son code, on ajoute celui d'un ami.
/// C'est un cercle de gens qui se connaissent, pas un réseau public. La page se
/// tient donc comme un registre d'atelier : un cartouche en tête, des sections
/// en petites capitales, et les activités portées l'une sous l'autre.
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
    final p = context.palette;
    final moi = ref.watch(cercleMoiProvider);
    final amis = ref.watch(amisProvider);
    final demandes = ref.watch(demandesProvider).valueOrNull ?? const Demandes();
    final fil = ref.watch(filProvider);
    final recus = ref.watch(encouragementsProvider).valueOrNull ?? const [];
    final nouveaux = recus.where((e) => e.nouveau).toList();
    _marquerVus(recus);

    return Scaffold(
      appBar: AppBar(title: const Texte('Mon cercle')),
      // Le grain du papier : le cercle s'ouvre hors de la coque.
      body: FondPapier(
        child: SafeArea(
          top: false,
          bottom: false,
          child: moi.when(
            loading: () => const Padding(padding: EdgeInsets.all(20), child: SqueletteCarte(lignes: 5)),
            error: (e, _) => EtatErreur(erreur: e, reessayer: _rafraichir),
            data: (m) => RefreshIndicator(
              onRefresh: _rafraichir,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                children: [
                  Texte(
                    "Lire à plusieurs tient mieux dans la durée. Suivez vos amis, "
                    "encouragez-les et écrivez-leur.",
                    style: t.textTheme.bodyMedium?.copyWith(color: p.attenue, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  _CarteCode(moi: m),

                  if (demandes.recues.isNotEmpty) ...[
                    _Titre('demandes', compte: demandes.recues.length),
                    for (final d in demandes.recues) _LigneDemande(demande: d),
                  ],

                  if (nouveaux.isNotEmpty) ...[
                    _Titre('pour vous', compte: nouveaux.length),
                    for (final e in nouveaux) _CarteEncouragement(encouragement: e),
                  ],

                  const _Titre('fil de lecture'),
                  fil.when(
                    loading: () => const SqueletteCarte(lignes: 3),
                    error: (e, _) => const _Discret(
                      "Le fil n'a pas pu se charger. Tirez vers le bas pour réessayer.",
                      scene: Scene.sansReseau,
                    ),
                    data: (evenements) => evenements.isEmpty
                        ? const _Discret(
                            "Rien encore ces quatorze derniers jours. Les séances et les quiz de vos amis "
                            "apparaîtront ici.",
                            scene: Scene.pageBlanche)
                        : _Fil(evenements: evenements.take(20).toList()),
                  ),

                  const _Titre('mes amis'),
                  amis.when(
                    loading: () => const SqueletteCarte(lignes: 3),
                    error: (e, _) => EtatErreur(erreur: e, reessayer: _rafraichir),
                    data: (liste) => liste.isEmpty
                        ? const _Discret(
                            "Votre cercle est vide pour l'instant. Partagez votre code, ou ajoutez celui "
                            "d'un ami : l'amitié commence dès qu'il accepte.",
                            scene: Scene.cercleVide)
                        : Column(children: [for (final a in liste) _LigneAmi(ami: a)]),
                  ),
                  if (demandes.envoyees.isNotEmpty) ...[
                    _EnAttente('En attente de réponse : ${demandes.envoyees.map((d) => d.lecteur.nom).join(', ')}.'),
                  ],

                  const _Titre('confidentialité'),
                  _Partage(actif: m.partageActivite),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le titre d'une section du registre : petites capitales entre crochets, le
/// nombre d'éléments en folio à droite, et le filet d'imprimeur dessous.
class _Titre extends StatelessWidget {
  const _Titre(this.texte, {this.compte});
  final String texte;
  final int? compte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(child: EtiquetteCrochet(texte)),
              if (compte != null) ...[
                const Spacer(),
                Texte('$compte',
                    style: t.textTheme.labelSmall?.copyWith(
                      color: p.accentTexte,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    )),
              ],
            ],
          ),
          const SizedBox(height: 8),
          const Filet(redouble: true),
        ],
      ),
    );
  }
}

/// Une remarque en ligne, sous une liste : pas de bloc, une icône et le texte.
class _EnAttente extends StatelessWidget {
  const _EnAttente(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: IconeAscenda(Icone.signet, taille: 15, couleur: p.attenue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Texte(texte, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.attenue)),
          ),
        ],
      ),
    );
  }
}

/// Un bloc creusé qui dit ce qui manque : un cercle encore vide, un fil sans
/// activité, un serveur qui n'a pas répondu.
///
/// La scène raconte le moment plutôt qu'elle ne le constate : une icône grise
/// ne dit rien à quelqu'un qui vient d'arriver.
class _Discret extends StatelessWidget {
  const _Discret(this.texte, {required this.scene});
  final String texte;
  final Scene scene;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: p.surfaceCreuse,
        borderRadius: Rayons.carte,
        border: Border.all(color: p.encre.withValues(alpha: p.sombre ? 0.18 : 0.09)),
      ),
      child: Column(
        children: [
          Illustration(scene, taille: 150),
          const SizedBox(height: 12),
          Texte(
            texte,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.attenue, height: 1.55),
          ),
        ],
      ),
    );
  }
}

class AvatarLecteur extends StatelessWidget {
  const AvatarLecteur({super.key, required this.lecteur, this.taille = 42});
  final Lecteur lecteur;
  final double taille;

  @override
  Widget build(BuildContext context) {
    // Une teinte stable par lecteur, prise dans celles des pôles : un visage se
    // reconnaît à sa couleur avant son nom. Les teintes de pôle sont fixes,
    // l'initiale est donc blanche dans tous les thèmes.
    final teintes = Couleurs.poles.values.toList();
    final teinte = teintes[lecteur.id.codeUnits.fold(0, (a, b) => a + b) % teintes.length];
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(teinte, Colors.white, 0.18)!, teinte],
        ),
        boxShadow: [BoxShadow(color: teinte.withValues(alpha: 0.28), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Texte(
        lecteur.initiale,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: taille * 0.42),
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
    final p = context.palette;
    return SurfaceHeros(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accentSurHeros.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: p.accentSurHeros.withValues(alpha: 0.32)),
                ),
                child: IconeAscenda(Icone.cercle, taille: 23, couleur: p.accentSurHeros),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EtiquetteCrochet('votre code ASCENDA', couleur: p.accentSurHeros),
                    const SizedBox(height: 4),
                    Texte(
                      'À transmettre à vos amis',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Le code frappé dans un cartouche : deux filets d'or, rien d'autre.
          // C'est un objet à recopier, pas un champ de formulaire.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            decoration: BoxDecoration(
              color: p.surHeros.withValues(alpha: 0.07),
              border: Border.all(color: p.accentSurHeros.withValues(alpha: 0.5), width: 1.2),
              borderRadius: Rayons.petit,
            ),
            child: Column(
              children: [
                SizedBox(width: 90, child: Filet(couleur: p.accentSurHeros.withValues(alpha: 0.45))),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SelectableText(
                    moi.code,
                    key: const Key('code-cercle'),
                    style: t.textTheme.headlineMedium?.copyWith(
                      color: p.accentSurHeros,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(width: 90, child: Filet(couleur: p.accentSurHeros.withValues(alpha: 0.45))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _inviter(context),
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Texte('Inviter', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.surHeros,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
                    side: BorderSide(color: p.accentSurHeros.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _ajouter(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Texte('Ajouter', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.surAccent,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
                  ),
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
    final p = context.palette;
    return AlertDialog(
      icon: const IconePastille(Icons.person_add_alt_1_rounded, taille: 52),
      title: const Texte('Ajouter un ami', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Texte("Saisissez le code ASCENDA qu'il vous a transmis.",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.attenue)),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 2),
            decoration: InputDecoration(
              labelText: 'Code',
              hintText: 'AWA-7KQ2',
              prefixIcon: const Icon(Icons.tag_rounded),
              errorText: _erreur,
              errorMaxLines: 3,
            ),
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
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Surface(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarLecteur(lecteur: demande.lecteur, taille: 44),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Texte(demande.lecteur.nom,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                      const SizedBox(height: 1),
                      Texte('veut rejoindre votre cercle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _repondre(context, ref, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.attenue,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      side: BorderSide(color: p.trait),
                      shape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
                    ),
                    child: const Texte('Refuser', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _repondre(context, ref, true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
                    ),
                    child: const Texte('Accepter', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ),
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
    final p = context.palette;
    final e = encouragement;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: Rayons.carte,
          boxShadow: p.ombreCarte,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(p.accentVoile, p.surface),
              p.surface,
            ],
          ),
          border: Border.all(color: p.accentTexte.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconePastille(iconeGenre(e.genre), taille: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte('« ${e.message} »',
                        style: t.textTheme.titleLarge?.copyWith(fontSize: 17.5, height: 1.4, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        AvatarLecteur(lecteur: e.auteur, taille: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Texte(
                            [e.auteur.nom, if (e.ouvrage != null) e.ouvrage!, ilYA(e.le)].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
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

/// Le fil : un registre d'atelier. Une seule feuille, les activités portées
/// l'une sous l'autre, séparées d'un filet d'imprimeur.
class _Fil extends StatelessWidget {
  const _Fil({required this.evenements});
  final List<EvenementFil> evenements;

  @override
  Widget build(BuildContext context) {
    return Surface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < evenements.length; i++) ...[
            if (i > 0) const Padding(padding: EdgeInsets.only(left: 50), child: Filet()),
            _LigneFil(evenement: evenements[i]),
          ],
        ],
      ),
    );
  }
}

class _LigneFil extends ConsumerWidget {
  const _LigneFil({required this.evenement});
  final EvenementFil evenement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final e = evenement;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarLecteur(lecteur: e.lecteur, taille: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: e.lecteur.nom, style: TextStyle(fontWeight: FontWeight.w700, color: p.encre)),
                    TextSpan(text: ' ${lisible(e.texte)}'),
                  ]),
                  style: t.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
                if (e.ouvrage != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      IconeAscenda(Icone.volumes, taille: 14, couleur: p.accentTexte),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Texte(e.ouvrage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodySmall?.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Texte(ilYA(e.le),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 0.6)),
                    ),
                    if (e.encourage) ...[
                      const SizedBox(width: 8),
                      // Le sceau apposé : cette activité a déjà reçu son mot.
                      Semantics(
                        label: 'Encouragé',
                        child: IconeAscenda(Icone.sceau, taille: 16, couleur: p.succes),
                      ),
                    ],
                    const Spacer(),
                    if (!e.encourage)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: const Size(0, 34),
                          foregroundColor: p.accentTexte,
                          side: BorderSide(color: p.accentTexte.withValues(alpha: 0.45)),
                          shape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
                        ),
                        onPressed: () => encourager(context, ref, e.lecteur, evenement: e),
                        child: const Texte('Encourager'),
                      ),
                  ],
                ),
              ],
            ),
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
    final p = context.palette;
    final l = ami.lecture;
    final resume = !l.partage
        ? "ne partage pas son activité"
        : l.seancesSemaine == 0
            ? (l.derniereActivite != null ? 'dernière lecture ${ilYA(l.derniereActivite)}' : 'pas encore de séance')
            : '${l.seancesSemaine} séance${l.seancesSemaine > 1 ? 's' : ''} · ${l.minutesSemaine} min cette semaine';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Surface(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        onTap: () => context.push('/cercle/ami/${ami.lecteur.id}?nom=${Uri.encodeComponent(ami.lecteur.nom)}'),
        child: Row(
          children: [
            AvatarLecteur(lecteur: ami.lecteur, taille: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Texte(ami.lecteur.nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Texte(resume, style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
                  if (l.partage && l.lit != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        IconeAscenda(Icone.signet, taille: 14, couleur: p.accentTexte),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Texte('lit ${l.lit}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodySmall?.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (ami.nonLus > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.accent, borderRadius: Rayons.pilule),
                child: Texte('${ami.nonLus}',
                    style: t.textTheme.labelSmall?.copyWith(color: p.surAccent, fontWeight: FontWeight.w700)),
              )
            else
              Icon(Icons.chevron_right_rounded, color: p.attenue),
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
    final p = context.palette;
    return Surface(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
        value: _actif,
        secondary: IconePastille(_actif ? Icons.visibility_outlined : Icons.visibility_off_outlined, taille: 40),
        title: const Texte('Montrer ma lecture à mes amis'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Texte(
            "Vos séances et vos quiz apparaissent dans leur fil. Vos notes, vos réponses et "
            "vos échanges restent privés dans tous les cas.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.attenue),
          ),
        ),
        onChanged: (v) async {
          setState(() => _actif = v);
          try {
            await ref.read(clientApiProvider).patch('/cercle/preferences', corps: {'partage_activite': v});
          } catch (_) {
            if (mounted) setState(() => _actif = !v);
          }
        },
      ),
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
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarLecteur(lecteur: widget.ami, taille: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Texte('Encourager ${widget.ami.nom}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.titleLarge?.copyWith(fontSize: 19)),
                      if (widget.evenement != null) ...[
                        const SizedBox(height: 2),
                        Texte('${widget.ami.nom} ${widget.evenement!.texte}',
                            style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final (cle, libelle) in _genres) ...[
              _ChoixGenre(
                icone: iconeGenre(cle),
                libelle: libelle,
                choisi: _genre == cle,
                onTap: () => setState(() => _genre = cle),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            TextField(
              controller: _mot,
              maxLength: 280,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Un mot à vous (facultatif)', errorText: _erreur),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _envoi ? null : _envoyer,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  shape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
                ),
                child: const Texte('Envoyer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un message prêt à envoyer, choisi d'une touche : la carte s'allume en or.
class _ChoixGenre extends StatelessWidget {
  const _ChoixGenre({required this.icone, required this.libelle, required this.choisi, required this.onTap});

  final IconData icone;
  final String libelle;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Semantics(
      selected: choisi,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: choisi ? Color.alphaBlend(p.accentVoile, p.surface) : p.surface,
          borderRadius: Rayons.carte,
          border: Border.all(color: choisi ? p.accentTexte : p.trait, width: choisi ? 1.6 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: Rayons.carte,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
              child: Row(
                children: [
                  IconePastille(icone, taille: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Texte(libelle,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: p.encre,
                          fontWeight: choisi ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    choisi ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: choisi ? p.accentTexte : p.attenue.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
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
        icon: Icon(Icons.flag_outlined, color: c.palette.alerte),
        title: const Texte('Signaler ce message', textAlign: TextAlign.center),
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
    final p = context.palette;
    final conv = ref.watch(conversationProvider(widget.amiId));
    final ami = conv.valueOrNull?.ami ?? Lecteur(id: widget.amiId, nom: widget.nom ?? 'Conversation');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AvatarLecteur(lecteur: ami, taille: 36),
            const SizedBox(width: 12),
            Flexible(child: Texte(ami.nom, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: const RoundedRectangleBorder(borderRadius: Rayons.moyen),
            onSelected: (c) => _menu(c, ami),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'encourager', child: Texte('Encourager')),
              PopupMenuItem(value: 'retirer', child: Texte('Retirer du cercle')),
              PopupMenuItem(value: 'bloquer', child: Texte('Bloquer')),
            ],
          ),
        ],
      ),
      body: FondPapier(
        child: SafeArea(
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
                          scene: Scene.pageBlanche,
                          titre: 'Écrivez à ${c.ami.nom}',
                          texte: "Où en êtes-vous de vos lectures ? Une question sur un chapitre, un livre "
                              "à conseiller : c'est l'endroit.",
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          itemCount: c.messages.length,
                          itemBuilder: (_, i) {
                            final m = c.messages[c.messages.length - 1 - i];
                            return _Bulle(message: m, onSignaler: m.deMoi ? null : () => _signaler(m));
                          },
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: ZoneMessage(
                  controleur: _saisie,
                  attente: _envoi,
                  lignesMax: 5,
                  longueurMax: 2000,
                  onEnvoyer: _envoyer,
                ),
              ),
              if (conv.hasValue)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 20, right: 20),
                  child: Texte('Appui long sur un message reçu pour le signaler.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.labelSmall?.copyWith(color: p.attenue)),
                ),
            ],
          ),
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
    final p = context.palette;
    final m = message;
    return Align(
      alignment: m.deMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onSignaler,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 8),
          // Un billet plié : trois coins arrondis, le quatrième presque vif, du
          // côté de celui qui l'a écrit.
          decoration: BoxDecoration(
            color: m.deMoi ? null : p.surface,
            gradient: m.deMoi ? p.degradeHeros : null,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(m.deMoi ? 16 : 5),
              bottomRight: Radius.circular(m.deMoi ? 5 : 16),
            ),
            border: m.deMoi ? null : Border.all(color: p.encre.withValues(alpha: p.sombre ? 0.22 : 0.12)),
            boxShadow: m.deMoi
                ? [BoxShadow(color: p.heros.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 4))]
                : p.ombreCarte,
          ),
          child: Column(
            crossAxisAlignment: m.deMoi ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Texte(m.texte,
                  textAlign: TextAlign.start,
                  style: t.textTheme.bodyMedium?.copyWith(color: m.deMoi ? p.surHeros : p.texte, height: 1.45)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Texte(
                    ilYA(m.le),
                    style: t.textTheme.labelSmall?.copyWith(color: m.deMoi ? p.surHerosDoux : p.attenue),
                  ),
                  if (m.deMoi && m.lu) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.done_all_rounded, size: 14, color: p.accentSurHeros, semanticLabel: 'lu'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
