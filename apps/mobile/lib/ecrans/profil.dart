import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/modeles.dart';

import '../api/libelles.dart';
import '../etat/fournisseurs.dart';
import '../etat/hors_ligne.dart';
import '../etat/session.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../widgets/etats.dart';
import '../widgets/selecteur_theme.dart';
import '../widgets/ui.dart';
import 'auth.dart';
import '../theme/texte.dart';

/// Le profil : la page de garde du lecteur.
///
/// Son initiale y est frappée comme un ex-libris, sa formule tient dans un
/// cartouche, ses compteurs se remplissent comme des jauges d'imprimeur et ses
/// réglages se suivent, séparés par des filets. La page se ferme sur un
/// fleuron et la marque, comme un volume se ferme sur son achevé d'imprimer.
class EcranProfil extends ConsumerWidget {
  const EcranProfil({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final compte = ref.watch(compteProvider);
    final usage = ref.watch(usageProvider);
    final t = Theme.of(context);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Texte('Profil'),
        actions: [
          // La déconnexion vit dans la barre du haut, pas au fond d'une page
          // qu'il faut faire défiler. C'est le geste qu'on cherche quand on
          // prête son téléphone.
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout_rounded, size: 21),
            onPressed: () => _confirmerDeconnexion(context, ref),
          ),
          const SizedBox(width: 6),
        ],
      ),
      // Le grain du papier : le profil s'ouvre hors de la coque, il ne l'hérite
      // donc pas du tiroir.
      body: FondPapier(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            children: [
              // La page se pose bloc par bloc, une fois, à l'ouverture.
              Apparition(child: _EnTeteCompte(premium: session.premium)),
              const SizedBox(height: 14),
              const Apparition(rang: 1, child: _EntreeCodes()),
              const SizedBox(height: 28),
              const Apparition(
                rang: 2,
                child: TitreSection(
                  'Vos compteurs',
                  sousTitre: "Ce qui coûte à ASCENDA, c'est d'indexer des documents et de faire "
                      "réfléchir l'agent. Le reste est libre.",
                ),
              ),
              const SizedBox(height: 12),
              Apparition(
                rang: 2,
                child: usage.when(
                  loading: () => const Squelette(hauteur: 120, rayon: 20),
                  error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(usageProvider)),
                  data: (u) {
                    final compteurs = [
                      for (final c in (u['compteurs'] as List).cast<Map<String, dynamic>>())
                        if (c['limite'] != null) c,
                    ];
                    if (compteurs.isEmpty) return const SizedBox.shrink();
                    return Surface(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < compteurs.length; i++) ...[
                            if (i > 0) ...[
                              const SizedBox(height: 14),
                              const Filet(),
                              const SizedBox(height: 14),
                            ],
                            _Compteur(
                              libelle: libellesQuota[compteurs[i]['type']] ?? '${compteurs[i]['type']}',
                              utilise: compteurs[i]['utilise'] as int? ?? 0,
                              limite: compteurs[i]['limite'] as int,
                              periode: '${compteurs[i]['periode']}',
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              const Apparition(
                rang: 3,
                child: TitreSection('Apparence', sousTitre: 'Le papier de lecture, ou automatique selon le téléphone.'),
              ),
              const SizedBox(height: 12),
              const Apparition(
                rang: 3,
                child: Surface(
                  padding: EdgeInsets.fromLTRB(14, 18, 14, 16),
                  child: SelecteurTheme(),
                ),
              ),
              compte.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (c) {
                  final profil = c['profil'] as Map<String, dynamic>?;
                  if (profil == null) return const SizedBox.shrink();
                  return Apparition(
                    rang: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const TitreSection('Votre profil de lecture'),
                          const SizedBox(height: 12),
                          Surface(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Ligne(
                                  icone: Icone.pousse,
                                  cle: 'Niveau',
                                  valeur: _niveau(profil['niveau']),
                                ),
                                const _FiletLigne(retrait: 38),
                                _Ligne(
                                  icone: Icone.boussole,
                                  cle: 'Objectif',
                                  valeur: _objectif(profil['objectif']),
                                ),
                                const _FiletLigne(retrait: 38),
                                _Ligne(
                                  icone: Icone.soleil,
                                  cle: 'Temps hebdomadaire',
                                  valeur: profil['minutes_semaine'] == null
                                      ? 'non renseigné'
                                      : '${((profil['minutes_semaine'] as int) / 60).round()} h par semaine',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => context.push('/diagnostic'),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Texte('Refaire le diagnostic'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
              const Apparition(rang: 5, child: TitreSection('Sur cet appareil')),
              const SizedBox(height: 12),
              const Apparition(rang: 5, child: _EntreeHorsLigne()),
              const SizedBox(height: 28),
              const Apparition(rang: 6, child: TitreSection('Compte et sécurité')),
              const SizedBox(height: 12),
              Apparition(
                rang: 6,
                child: Surface(
                  padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LigneReglage(
                        icone: Icone.page,
                        titre: 'Droits et citations',
                        detail: 'Pourquoi certains ouvrages ne sont pas lisibles ici',
                        onTap: () => _expliquerDroits(context),
                      ),
                      const _FiletLigne(),
                      _LigneReglage(
                        icone: Icone.clef,
                        titre: 'Changer mon mot de passe',
                        detail: 'Ferme toutes vos sessions ouvertes.',
                        onTap: () => context.push('/mot-de-passe'),
                      ),
                      const _FiletLigne(),
                      _LigneReglage(
                        icone: Icone.lecteur,
                        titre: 'Fermer toutes mes sessions',
                        detail: 'Sur un appareil perdu ou prêté, referme tout de suite.',
                        onTap: () => _fermerPartout(context, ref),
                      ),
                      const _FiletLigne(),
                      _LigneReglage(
                        icone: Icone.fleche,
                        titre: 'Se déconnecter',
                        couleur: p.alerte,
                        onTap: () => _confirmerDeconnexion(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // L'achevé d'imprimer : le fleuron, la marque, la devise.
              Apparition(
                rang: 7,
                child: Column(
                  children: [
                    const Fleuron(),
                    const SizedBox(height: 18),
                    const MarqueAscenda(taille: 34),
                    const SizedBox(height: 8),
                    Texte('ASCENDA · Learn. Grow. Become.',
                        style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 0.6)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _niveau(dynamic v) => switch ('$v') {
        'debutant' => 'Débutant',
        'intermediaire' => 'Intermédiaire',
        'avance' => 'Avancé',
        _ => 'Non évalué',
      };

  static String _objectif(dynamic v) => switch ('$v') {
        'curiosite' => 'Comprendre par curiosité',
        'professionnel' => 'Usage professionnel',
        'examen' => 'Préparer un examen',
        'culture' => 'Me constituer une culture',
        _ => 'non renseigné',
      };

  /// Se déconnecter efface la session : on demande confirmation, parce que
  /// retrouver son mot de passe sur un téléphone n'est pas toujours simple.
  /// Révoque toutes les sessions, celle-ci comprise.
  ///
  /// Le serveur ne fait pas d'exception pour l'appareil qui demande : il coupe
  /// tous les jetons de rafraîchissement du compte. Écrire « celui-ci reste
  /// ouvert » serait faux, et le mensonge se découvrirait une demi-heure plus
  /// tard, à l'expiration du jeton d'accès, par une déconnexion inexpliquée.
  /// On sort donc franchement, tout de suite.
  Future<void> _fermerPartout(BuildContext context, WidgetRef ref) async {
    final oui = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Texte('Fermer toutes les sessions ?'),
        content: const Texte(
          "Tous vos appareils devront se reconnecter, y compris celui-ci. "
          "Votre progression et vos notes sont conservées.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Texte('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Texte('Fermer')),
        ],
      ),
    );
    if (oui != true) return;
    try {
      await ref.read(clientApiProvider).post('/auth/deconnexion-partout');
      await ref.read(sessionProvider.notifier).deconnexion();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Texte('Toutes vos sessions sont fermées.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Texte("Les sessions n'ont pas pu être fermées.")),
        );
      }
    }
  }

  Future<void> _confirmerDeconnexion(BuildContext context, WidgetRef ref) async {
    final oui = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Texte('Se déconnecter'),
        content: const Texte(
          "Votre chronogramme, vos notes et votre progression sont conservés. "
          "Vous les retrouverez à la prochaine connexion.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Texte('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
              backgroundColor: c.palette.alerte,
              foregroundColor: c.palette.surface,
            ),
            child: const Texte('Se déconnecter'),
          ),
        ],
      ),
    );
    if (oui == true) {
      await ref.read(sessionProvider.notifier).deconnexion();
    }
  }

  void _expliquerDroits(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EtiquetteCrochet('droits et citations'),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Lettrine('D', taille: 54),
                const SizedBox(width: 14),
                Expanded(
                  child: Texte(
                    'Ce qui se lit ici, et ce qui se lit sur votre exemplaire',
                    style: Theme.of(c).textTheme.titleLarge?.copyWith(fontSize: 19, height: 1.25),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Filet(redouble: true),
            const SizedBox(height: 16),
            Texte(
              "Sur les 78 ouvrages du corpus, 7 sont librement redistribuables : "
              "domaine public, rapports institutionnels, documents sous licence "
              "ouverte. Ceux-là, vous pouvez les lire intégralement ici.\n\n"
              "Pour les 71 autres, ASCENDA cite des extraits courts avec leur page "
              "et ne reproduit pas le texte. Vous y gagnez la fiche, les idées-force, "
              "les quiz et le plan de lecture ; la lecture se fait sur votre "
              "exemplaire. C'est une limite assumée, pas un défaut technique.",
              style: Theme.of(c).textTheme.bodyMedium?.copyWith(height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'en-tête du compte : l'initiale frappée comme un ex-libris, le nom, puis
/// la formule en cours dans son cartouche. La seule carte de mise en avant de
/// la page.
class _EnTeteCompte extends ConsumerWidget {
  const _EnTeteCompte({required this.premium});
  final bool premium;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final u = ref.watch(sessionProvider).utilisateur;
    final abonnement = ref.watch(abonnementProvider).valueOrNull;
    final acces = u?.acces;
    // Le descriptif et le nom viennent du serveur, qui les lit dans les mêmes
    // tables que celles appliquant les limites. Recopiés ici, ils finissaient
    // par promettre autre chose que ce qui est réellement accordé. Les valeurs
    // en dur ne servent plus que de secours hors connexion.
    final formules = ref.watch(formulesProvider).valueOrNull;
    final formule = formules?.cast<Map<String, dynamic>?>().firstWhere(
          (f) => f?['code'] == (premium ? 'premium' : 'free'),
          orElse: () => null,
        );
    // La même initiale que sur l'avatar des onglets, mais frappée dans un
    // cadre à l'encre plutôt que posée dans un disque.
    final initiale =
        (u?.nom?.trim().isNotEmpty == true ? u!.nom!.trim()[0] : (u?.email?[0] ?? 'A')).toUpperCase();

    return SurfaceHeros(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EtiquetteCrochet('page de garde', couleur: p.accentSurHeros),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Lettrine(initiale, taille: 62, couleur: p.accentSurHeros),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte(
                      u?.nom ?? 'Votre compte',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 23, height: 1.15),
                    ),
                    if (u?.email != null) ...[
                      const SizedBox(height: 4),
                      Texte(
                        u!.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Filet(redouble: true, couleur: p.surHeros.withValues(alpha: 0.22)),
          const SizedBox(height: 16),
          // Le cartouche de la formule : un cadre d'or, comme la mention
          // portée au dos d'un volume.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
            decoration: BoxDecoration(
              color: p.surHeros.withValues(alpha: 0.06),
              borderRadius: Rayons.moyen,
              border: Border.all(color: p.accentSurHeros.withValues(alpha: 0.32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconeAscenda(
                      premium ? Icone.sceau : Icone.boussole,
                      taille: 26,
                      couleur: p.accentSurHeros,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Surtitre('Votre formule', couleur: p.surHerosDoux),
                          const SizedBox(height: 2),
                          Texte(
                            '${formule?['nom'] ?? (premium ? 'Ascension' : 'Découverte')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleLarge?.copyWith(fontSize: 19, color: p.accentSurHeros),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Filet(couleur: p.surHeros.withValues(alpha: 0.14)),
                const SizedBox(height: 10),
                Texte(
                  '${formule?['resume'] ?? (premium
                      ? "Vos documents, axes illimités, chronogramme adaptatif, "
                          "synthèses et quiz à la demande."
                      : "La bibliothèque de base, un axe, un chronogramme, les quiz "
                          "déjà préparés.")}',
                  style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux, height: 1.6),
                ),
                if (!premium && acces != null && acces.source != 'aucune') ...[
                  const SizedBox(height: 10),
                  _MentionHeros(
                    icone: Icone.jeton,
                    texte: _accesOffert(acces),
                    couleur: p.accentSurHeros,
                  ),
                ],
                if (premium && abonnement != null && abonnement.joursRestants != null) ...[
                  const SizedBox(height: 10),
                  _MentionHeros(
                    icone: abonnement.bientotEchu ? Icone.soleil : Icone.signet,
                    texte: abonnement.joursRestants == 0
                        ? "Votre accès se referme aujourd'hui."
                        : 'Il vous reste ${abonnement.joursRestants} jour'
                            '${abonnement.joursRestants! > 1 ? 's' : ''}.',
                    couleur: abonnement.bientotEchu ? p.accentSurHeros : p.surHerosDoux,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: premium
                ? OutlinedButton.icon(
                    onPressed: () => context.push('/abonnement'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.accentSurHeros,
                      side: BorderSide(color: p.accentSurHeros.withValues(alpha: 0.35)),
                    ),
                    icon: const Icon(Icons.update_rounded, size: 19),
                    label: const Texte('Prolonger mon accès'),
                  )
                : FilledButton.icon(
                    onPressed: () => context.push('/abonnement'),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    iconAlignment: IconAlignment.end,
                    label: const Texte('Passer à Ascension'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Une précision sur la carte du compte : icône à la plume et texte de même
/// teinte.
class _MentionHeros extends StatelessWidget {
  const _MentionHeros({required this.icone, required this.texte, required this.couleur});
  final Icone icone;
  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: IconeAscenda(icone, taille: 17, couleur: couleur),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Texte(
              texte,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: couleur, height: 1.45),
            ),
          ),
        ],
      );
}

String _accesOffert(AccesEffectif a) {
  final fin = a.jusquAu == null ? '' : " jusqu'au ${DateFormat('d MMMM', 'fr_FR').format(a.jusquAu!)}";
  if (a.source == 'lancement') return 'Période de lancement : tout est ouvert$fin.';
  if (a.complet) return 'Code actif : tout Ascension est ouvert$fin.';
  final n = a.fonctions.length;
  return 'Code actif : $n fonction${n > 1 ? 's' : ''} d\'Ascension ouverte${n > 1 ? 's' : ''}$fin.';
}

/// L'entrée vers les codes. La pastille compte les réductions gagnées que le
/// lecteur n'a pas encore vues : c'est la notification dans l'application.
class _EntreeCodes extends ConsumerWidget {
  const _EntreeCodes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final nouveaux = ref.watch(codesProvider).valueOrNull?.nouveaux ?? 0;
    return Surface(
      padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
      child: _LigneReglage(
        icone: Icone.jeton,
        titre: 'Codes et avantages',
        detail: 'Activer un code, partager le vôtre, vos réductions',
        onTap: () async {
          await context.push('/codes');
          ref.invalidate(codesProvider);
        },
        suffixe: nouveaux > 0
            ? Container(
                key: const Key('pastille-codes'),
                constraints: const BoxConstraints(minWidth: 24),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: p.alerte, borderRadius: Rayons.pilule),
                alignment: Alignment.center,
                child: Texte(
                  '$nouveaux',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: p.surface,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              )
            : null,
      ),
    );
  }
}

/// L'entrée vers les livres gardés sur l'appareil. La liste et la place
/// qu'elle prend vivent sur leur propre écran.
class _EntreeHorsLigne extends ConsumerWidget {
  const _EntreeHorsLigne();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final packs = ref.watch(packsProvider).valueOrNull;
    final nombre = packs?.length ?? 0;
    String? detail;
    if (packs != null) {
      if (nombre == 0) {
        detail = 'Aucun ouvrage emporté pour le moment';
      } else {
        final total = packs.values.fold<int>(0, (s, x) => s + x.octets);
        final poids = total < 1024 * 1024
            ? '${(total / 1024).round()} Ko'
            : '${(total / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
        detail = '$nombre ouvrage${nombre > 1 ? 's' : ''} disponible${nombre > 1 ? 's' : ''} sans réseau · $poids';
      }
    }
    return Surface(
      padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
      child: _LigneReglage(
        icone: Icone.signet,
        couleurIcone: p.succes,
        titre: 'Livres hors ligne',
        detail: detail,
        onTap: () => context.push('/hors-ligne'),
      ),
    );
  }
}

/// Une ligne de réglage : l'icône tracée à la plume, le titre et son détail,
/// le chevron. Rien n'est encadré : ce sont des lignes de cahier.
class _LigneReglage extends StatelessWidget {
  const _LigneReglage({
    required this.icone,
    required this.titre,
    required this.onTap,
    this.detail,
    this.couleur,
    this.couleurIcone,
    this.suffixe,
  });

  final Icone icone;
  final String titre;
  final String? detail;
  final VoidCallback onTap;

  /// La teinte de toute la ligne, pour une action à part (la déconnexion).
  final Color? couleur;
  final Color? couleurIcone;
  final Widget? suffixe;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Center(
                child: IconeAscenda(icone, taille: 23, couleur: couleur ?? couleurIcone ?? p.accentTexte),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Texte(
                    titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall?.copyWith(color: couleur ?? p.encre),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 3),
                    Texte(
                      detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                    ),
                  ],
                ],
              ),
            ),
            if (suffixe != null) ...[const SizedBox(width: 8), suffixe!],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 21, color: couleur ?? p.attenue),
          ],
        ),
      ),
    );
  }
}

/// Le filet entre deux lignes d'un groupe, en retrait sous l'icône.
class _FiletLigne extends StatelessWidget {
  const _FiletLigne({this.retrait = 46});

  /// Le filet part sous le texte, pas sous l'icône.
  final double retrait;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.only(left: retrait), child: const Filet());
}

/// Un compteur : le libellé, la mesure, et la jauge qui se remplit.
class _Compteur extends StatelessWidget {
  const _Compteur({
    required this.libelle,
    required this.utilise,
    required this.limite,
    required this.periode,
  });

  final String libelle;
  final int utilise;
  final int limite;
  final String periode;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final periodeTexte = switch (periode) {
      'day' => 'aujourd\'hui',
      'month' => 'ce mois-ci',
      _ => 'au total',
    };

    // Une fonction réservée n'est pas une jauge vide : une barre pleine et
    // rouge se lisait comme une erreur. On dit simplement ce qui l'ouvre.
    if (limite == 0) {
      return Row(
        children: [
          Expanded(child: Texte(libelle, style: t.textTheme.bodyMedium?.copyWith(color: p.texte))),
          const SizedBox(width: 8),
          const Pastille('avec Ascension', icone: Icons.lock_outline_rounded),
        ],
      );
    }

    final part = (utilise / limite).clamp(0.0, 1.0);
    final atteint = utilise >= limite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Texte(libelle, style: t.textTheme.bodyMedium?.copyWith(color: p.texte))),
            const SizedBox(width: 8),
            // Le chiffre monte jusqu'à sa valeur : on voit ce qu'on a consommé.
            CompteurAnime(
              utilise,
              style: t.textTheme.titleLarge?.copyWith(fontSize: 19, color: atteint ? p.alerte : p.encre),
            ),
            Texte(' / $limite', style: t.textTheme.labelMedium?.copyWith(color: p.attenue)),
          ],
        ),
        const SizedBox(height: 8),
        Jauge(valeur: part, couleur: atteint ? p.alerte : null),
        const SizedBox(height: 6),
        Texte(
          atteint ? 'limite atteinte $periodeTexte' : periodeTexte,
          style: t.textTheme.labelSmall?.copyWith(
            color: atteint ? p.alerte : p.attenue,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

/// Une ligne du profil de lecture : la clé à gauche, la réponse à droite.
class _Ligne extends StatelessWidget {
  const _Ligne({required this.icone, required this.cle, required this.valeur});
  final Icone icone;
  final String cle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Center(child: IconeAscenda(icone, taille: 19, couleur: p.accentTexte)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Texte(cle, style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Texte(
              valeur,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodyMedium?.copyWith(color: p.encre, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
