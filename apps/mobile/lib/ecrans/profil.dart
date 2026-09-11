import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/libelles.dart';
import '../etat/fournisseurs.dart';
import '../etat/hors_ligne.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';
import 'auth.dart';

class EcranProfil extends ConsumerWidget {
  const EcranProfil({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final compte = ref.watch(compteProvider);
    final usage = ref.watch(usageProvider);
    final t = Theme.of(context);
    final u = session.utilisateur;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          // La déconnexion vit dans la barre du haut, pas au fond d'une page
          // qu'il faut faire défiler. C'est le geste qu'on cherche quand on
          // prête son téléphone.
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout_rounded, size: 21),
            onPressed: () => _confirmerDeconnexion(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Couleurs.or.withValues(alpha: 0.14),
                    shape: BoxShape.rectangle,
                  ),
                  child: Center(
                    child: Text(
                      (u?.nom?.isNotEmpty == true
                              ? u!.nom![0]
                              : (u?.email?[0] ?? 'A'))
                          .toUpperCase(),
                      style: t.textTheme.headlineSmall?.copyWith(color: Couleurs.orTexte),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u?.nom ?? 'Votre compte', style: t.textTheme.titleLarge),
                      if (u?.email != null)
                        Text(u!.email!,
                            style: t.textTheme.bodySmall
                                ?.copyWith(color: Couleurs.grisChaud)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            _CarteFormule(premium: session.premium),
            const SizedBox(height: 26),
            Text('Vos compteurs', style: t.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              "Ce qui coûte à ASCENDA, c'est d'indexer des documents et de faire "
              "réfléchir l'agent. Le reste est libre.",
              style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
            ),
            const SizedBox(height: 14),
            usage.when(
              loading: () => const Squelette(hauteur: 120, rayon: 16),
              error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(usageProvider)),
              data: (u) => Column(
                children: [
                  for (final c in (u['compteurs'] as List).cast<Map<String, dynamic>>())
                    if (c['limite'] != null)
                      _Compteur(
                        libelle: libellesQuota[c['type']] ?? '${c['type']}',
                        utilise: c['utilise'] as int? ?? 0,
                        limite: c['limite'] as int,
                        periode: '${c['periode']}',
                      ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            compte.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (c) {
                final profil = c['profil'] as Map<String, dynamic>?;
                if (profil == null) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: t.colorScheme.surface,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Votre profil de lecture', style: t.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _Ligne(cle: 'Niveau', valeur: _niveau(profil['niveau'])),
                      _Ligne(cle: 'Objectif', valeur: _objectif(profil['objectif'])),
                      _Ligne(
                        cle: 'Temps hebdomadaire',
                        valeur: profil['minutes_semaine'] == null
                            ? 'non renseigné'
                            : '${((profil['minutes_semaine'] as int) / 60).round()} h par semaine',
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => context.push('/diagnostic'),
                        child: const Text('Refaire le diagnostic'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const _BibliothequeHorsLigne(),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.gavel_outlined, size: 21),
              title: const Text('Droits et citations'),
              subtitle: Text(
                'Pourquoi certains ouvrages ne sont pas lisibles ici',
                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
              ),
              onTap: () => _expliquerDroits(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key_outlined, size: 21),
              title: const Text('Changer mon mot de passe'),
              subtitle: Text(
                'Ferme toutes vos sessions ouvertes.',
                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
              ),
              onTap: () => context.push('/mot-de-passe'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.devices_other_outlined, size: 21),
              title: const Text('Fermer toutes mes sessions'),
              subtitle: Text(
                'Sur un appareil perdu ou prêté, referme tout de suite.',
                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
              ),
              onTap: () => _fermerPartout(context, ref),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout_rounded, size: 21, color: Couleurs.terracotta),
              title: const Text('Se déconnecter',
                  style: TextStyle(color: Couleurs.terracotta)),
              onTap: () => _confirmerDeconnexion(context, ref),
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const MarqueAscenda(taille: 34),
                  const SizedBox(height: 8),
                  Text('ASCENDA · Learn. Grow. Become.',
                      style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
                ],
              ),
            ),
          ],
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
        title: const Text('Fermer toutes les sessions ?'),
        content: const Text(
          "Tous vos appareils devront se reconnecter, y compris celui-ci. "
          "Votre progression et vos notes sont conservées.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Fermer')),
        ],
      ),
    );
    if (oui != true) return;
    try {
      await ref.read(clientApiProvider).post('/auth/deconnexion-partout');
      await ref.read(sessionProvider.notifier).deconnexion();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Toutes vos sessions sont fermées.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Les sessions n'ont pas pu être fermées.")),
        );
      }
    }
  }

  Future<void> _confirmerDeconnexion(BuildContext context, WidgetRef ref) async {
    final oui = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Se déconnecter'),
        content: const Text(
          "Votre chronogramme, vos notes et votre progression sont conservés. "
          "Vous les retrouverez à la prochaine connexion.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: Couleurs.terracotta),
            child: const Text('Se déconnecter'),
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
            Text('Droits et citations', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 14),
            Text(
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

class _CarteFormule extends ConsumerWidget {
  const _CarteFormule({required this.premium});
  final bool premium;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final abonnement = ref.watch(abonnementProvider).valueOrNull;
    // Le descriptif et le nom viennent du serveur, qui les lit dans les mêmes
    // tables que celles appliquant les limites. Recopiés ici, ils finissaient
    // par promettre autre chose que ce qui est réellement accordé. Les valeurs
    // en dur ne servent plus que de secours hors connexion.
    final formules = ref.watch(formulesProvider).valueOrNull;
    final formule = formules?.cast<Map<String, dynamic>?>().firstWhere(
          (f) => f?['code'] == (premium ? 'premium' : 'free'),
          orElse: () => null,
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: premium
            ? const LinearGradient(colors: [Couleurs.nuit, Couleurs.nuitProfond])
            : null,
        color: premium ? null : t.colorScheme.surface,
        borderRadius: BorderRadius.zero,
        border: premium
            ? null
            : Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                premium ? Icons.workspace_premium_rounded : Icons.explore_outlined,
                color: premium ? Couleurs.orClair : Couleurs.orTexte,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                '${formule?['nom'] ?? (premium ? 'Ascension' : 'Découverte')}',
                style: t.textTheme.titleLarge?.copyWith(
                  fontSize: 18,
                  color: premium ? const Color(0xFFF4F1E8) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${formule?['resume'] ?? (premium
                ? "Vos documents, axes illimités, chronogramme adaptatif, "
                    "synthèses et quiz à la demande."
                : "La bibliothèque de base, un axe, un chronogramme, les quiz "
                    "déjà préparés.")}',
            style: t.textTheme.bodySmall?.copyWith(
              color: premium ? const Color(0xFFB9C1D6) : Couleurs.grisChaud,
              height: 1.6,
            ),
          ),
          if (premium && abonnement != null && abonnement.joursRestants != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  abonnement.bientotEchu
                      ? Icons.notification_important_outlined
                      : Icons.event_available_outlined,
                  size: 17,
                  color: abonnement.bientotEchu ? Couleurs.orClair : const Color(0xFF8E99B4),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    abonnement.joursRestants == 0
                        ? "Votre accès se referme aujourd'hui."
                        : 'Il vous reste ${abonnement.joursRestants} jour'
                            '${abonnement.joursRestants! > 1 ? 's' : ''}.',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: abonnement.bientotEchu
                          ? Couleurs.orClair
                          : const Color(0xFF8E99B4),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: premium
                ? OutlinedButton(
                    onPressed: () => context.push('/abonnement'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Couleurs.orClair,
                      side: const BorderSide(color: Color(0x40E8C070)),
                    ),
                    child: const Text('Prolonger mon accès'),
                  )
                : FilledButton(
                    onPressed: () => context.push('/abonnement'),
                    child: const Text('Passer à Ascension'),
                  ),
          ),
        ],
      ),
    );
  }
}

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
    final part = limite == 0 ? 1.0 : (utilise / limite).clamp(0.0, 1.0);
    final periodeTexte = switch (periode) {
      'day' => 'aujourd\'hui',
      'month' => 'ce mois-ci',
      _ => 'au total',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(libelle, style: t.textTheme.bodyMedium)),
              Text(
                limite == 0 ? 'Ascension' : '$utilise / $limite',
                style: t.textTheme.labelMedium?.copyWith(
                  color: limite == 0 ? Couleurs.orTexte : Couleurs.grisChaud,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.zero,
            child: LinearProgressIndicator(
              value: part,
              minHeight: 5,
              backgroundColor: t.colorScheme.surfaceContainer,
              color: part >= 1 ? Couleurs.terracotta : Couleurs.or,
            ),
          ),
          const SizedBox(height: 3),
          Text(periodeTexte,
              style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.cle, required this.valeur});
  final String cle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(cle,
                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
          ),
          Text(valeur, style: t.textTheme.bodyMedium),
        ],
      ),
    );
  }
}


/// Ce qui est stocké sur l'appareil, et de quoi le libérer.
class _BibliothequeHorsLigne extends ConsumerWidget {
  const _BibliothequeHorsLigne();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(packsProvider);
    final t = Theme.of(context);

    return packs.maybeWhen(
      data: (m) {
        if (m.isEmpty) return const SizedBox.shrink();
        final total = m.values.fold<int>(0, (s, p) => s + p.octets);
        final poids = total < 1024 * 1024
            ? '${(total / 1024).round()} Ko'
            : '${(total / (1024 * 1024)).toStringAsFixed(1)} Mo';
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.offline_pin_rounded, size: 19, color: Couleurs.sauge),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Disponible hors ligne', style: t.textTheme.titleMedium),
                  ),
                  Text(poids,
                      style: t.textTheme.labelMedium?.copyWith(color: Couleurs.grisChaud)),
                ],
              ),
              const SizedBox(height: 12),
              for (final p in m.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.titre,
                                style: t.textTheme.bodyMedium,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            Text(
                              '${p.compteurs['questions'] ?? 0} questions · ${p.poids}',
                              style: t.textTheme.labelSmall
                                  ?.copyWith(color: Couleurs.grisChaud),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: "Retirer de l'appareil",
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () async {
                          await ref.read(depotHorsLigneProvider).supprimer(p.documentId);
                          ref.invalidate(packsProvider);
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
