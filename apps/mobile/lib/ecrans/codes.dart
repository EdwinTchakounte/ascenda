import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';

String _jour(DateTime? d) =>
    d == null ? 'date à confirmer' : DateFormat('d MMMM y', 'fr_FR').format(d);

/// Codes et avantages : ce qu'un code a ouvert, le code à partager, et les
/// réductions qu'il a rapportées.
///
/// L'ordre suit ce qu'on vient chercher. On arrive ici avec un code reçu, donc
/// la saisie d'abord ; ensuite ce qui est ouvert et jusqu'à quand ; enfin son
/// propre code, qui est ce qu'on revient consulter pour le partager.
class EcranCodes extends ConsumerStatefulWidget {
  const EcranCodes({super.key});

  @override
  ConsumerState<EcranCodes> createState() => _EcranCodesState();
}

class _EcranCodesState extends ConsumerState<EcranCodes> {
  final _saisie = TextEditingController();
  bool _envoi = false;
  String? _erreur;
  bool _vusSignales = false;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  Future<void> _activer() async {
    final code = _saisie.text.trim();
    if (code.isEmpty) {
      setState(() => _erreur = 'Saisissez le code reçu.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final j =
          await ref
                  .read(clientApiProvider)
                  .post('/codes/activer', corps: {'code': code})
              as Map<String, dynamic>;
      _saisie.clear();
      // Tout ce qui dépend des plafonds doit se relire tout de suite : le
      // lecteur vient d'obtenir un accès, il ne doit pas avoir à relancer
      // l'application pour le voir.
      await ref.read(sessionProvider.notifier).rafraichirUtilisateur();
      ref.invalidate(codesProvider);
      ref.invalidate(usageProvider);
      ref.invalidate(compteProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${j['message'] ?? 'Code activé.'}')),
        );
    } on HorsLigne {
      setState(
        () => _erreur = 'Pas de connexion. Vérifiez votre réseau et réessayez.',
      );
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.message);
    } catch (_) {
      setState(() => _erreur = "Le code n'a pas pu être vérifié.");
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// La bonne nouvelle se montre une fois. On le signale au serveur dès que
  /// l'écran l'a affichée, sans rafraîchir : la pastille « Nouveau » reste
  /// visible le temps de cette visite.
  void _signalerVus(CodesEtAvantages c) {
    if (_vusSignales || c.nouveaux == 0) return;
    _vusSignales = true;
    ref.read(clientApiProvider).post('/codes/bons/vus').catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final donnees = ref.watch(codesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Codes et avantages')),
      body: SafeArea(
        bottom: false,
        child: donnees.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SqueletteCarte(lignes: 5),
          ),
          error: (e, _) => EtatErreur(
            erreur: e,
            reessayer: () => ref.invalidate(codesProvider),
          ),
          data: (c) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _signalerVus(c),
            );
            return RefreshIndicator(
              color: Couleurs.or,
              onRefresh: () async => ref.invalidate(codesProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                children: [
                  _Saisie(
                    controleur: _saisie,
                    envoi: _envoi,
                    erreur: _erreur,
                    onActiver: _activer,
                  ),
                  const SizedBox(height: 28),
                  _SectionAcces(donnees: c),
                  const SizedBox(height: 28),
                  _CarteAmbassadeur(donnees: c),
                  const SizedBox(height: 28),
                  _SectionReductions(donnees: c),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Saisie extends StatelessWidget {
  const _Saisie({
    required this.controleur,
    required this.envoi,
    required this.erreur,
    required this.onActiver,
  });

  final TextEditingController controleur;
  final bool envoi;
  final String? erreur;
  final VoidCallback onActiver;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Activer un code', style: t.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          "Un code reçu d'ASCENDA ouvre tout ou partie d'Ascension, pour une durée donnée.",
          style: t.textTheme.bodySmall?.copyWith(
            color: Couleurs.grisChaud,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('saisie-code'),
                controller: controleur,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onActiver(),
                style: const TextStyle(
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Votre code',
                  errorText: erreur,
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: envoi ? null : onActiver,
                child: envoi
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Text('Activer'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionAcces extends StatelessWidget {
  const _SectionAcces({required this.donnees});
  final CodesEtAvantages donnees;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = donnees.acces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Vos accès', style: t.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (a.source == 'abonnement')
          _LigneAcces(
            icone: Icons.workspace_premium_rounded,
            titre: 'Abonnement Ascension',
            detail: "Tout est ouvert jusqu'au ${_jour(a.jusquAu)}.",
          ),
        if (a.source == 'lancement')
          _LigneAcces(
            icone: Icons.celebration_outlined,
            titre: 'Période de lancement',
            detail: a.jusquAu == null
                ? 'Tout ASCENDA est ouvert à tous.'
                : "Tout ASCENDA est ouvert à tous jusqu'au ${_jour(a.jusquAu)}.",
          ),
        for (final code in a.codes) ...[
          _CarteCode(code: code, donnees: donnees),
          const SizedBox(height: 10),
        ],
        if (a.source == 'aucune')
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.colorScheme.surface,
              border: Border.all(
                color: t.dividerTheme.color ?? Couleurs.traitClair,
              ),
            ),
            child: Text(
              "Vous êtes sur l'offre Découverte. Un code ou un abonnement ouvre le reste.",
              style: t.textTheme.bodySmall?.copyWith(
                color: Couleurs.grisChaud,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _LigneAcces extends StatelessWidget {
  const _LigneAcces({
    required this.icone,
    required this.titre,
    required this.detail,
  });
  final IconData icone;
  final String titre;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Couleurs.or.withValues(alpha: 0.10),
        border: Border.all(color: Couleurs.or.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icone, color: Couleurs.orTexte, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: t.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: t.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteCode extends StatelessWidget {
  const _CarteCode({required this.code, required this.donnees});
  final AccesCode code;
  final CodesEtAvantages donnees;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bientot = code.joursRestants <= 3;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: Border(
          left: const BorderSide(color: Couleurs.or, width: 3),
          top: BorderSide(color: t.dividerTheme.color ?? Couleurs.traitClair),
          right: BorderSide(color: t.dividerTheme.color ?? Couleurs.traitClair),
          bottom: BorderSide(
            color: t.dividerTheme.color ?? Couleurs.traitClair,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(code.libelle, style: t.textTheme.titleSmall),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                color: Couleurs.nuit,
                child: Text(
                  code.code,
                  style: const TextStyle(
                    color: Couleurs.orClair,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            code.complet ? 'Tout Ascension' : 'Accès limité à :',
            style: t.textTheme.bodySmall?.copyWith(
              color: Couleurs.orTexte,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!code.complet) ...[
            const SizedBox(height: 6),
            for (final f in code.fonctions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Couleurs.sauge,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        donnees.libelle(f),
                        style: t.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                bientot
                    ? Icons.hourglass_bottom_rounded
                    : Icons.event_available_outlined,
                size: 16,
                color: bientot ? Couleurs.terracotta : Couleurs.grisChaud,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  code.joursRestants == 0
                      ? "Se referme aujourd'hui."
                      : "Jusqu'au ${_jour(code.fin)}, encore ${code.joursRestants} jour"
                            "${code.joursRestants > 1 ? 's' : ''}.",
                  style: t.textTheme.labelSmall?.copyWith(
                    color: bientot ? Couleurs.terracotta : Couleurs.grisChaud,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarteAmbassadeur extends StatelessWidget {
  const _CarteAmbassadeur({required this.donnees});
  final CodesEtAvantages donnees;

  Future<void> _copier(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: donnees.code));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Code copié.')));
    }
  }

  Future<void> _partager(BuildContext context) async {
    final lien = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(donnees.messagePartage)}',
    );
    if (!await launchUrl(lien, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: donnees.messagePartage));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "WhatsApp n'est pas disponible : le message est copié.",
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const clair = Color(0xFFF4F1E8);
    const doux = Color(0xFFB9C1D6);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Couleurs.nuit, Couleurs.nuitProfond],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.volunteer_activism_outlined,
                color: Couleurs.orClair,
                size: 20,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Votre code ambassadeur',
                  style: t.textTheme.titleMedium?.copyWith(color: clair),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SelectableText(
                donnees.code,
                key: const Key('code-ambassadeur'),
                style: const TextStyle(
                  color: Couleurs.orClair,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            donnees.programmeActif
                ? "Chaque personne qui crée son compte avec ce code vous offre "
                      "${donnees.pourcent} % de réduction sur votre prochain abonnement, "
                      "valable ${donnees.validiteJours} jours."
                : "Le programme ambassadeur est suspendu pour le moment. Votre code reste le vôtre.",
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall?.copyWith(color: doux, height: 1.6),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copier(context),
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('Copier'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Couleurs.orClair,
                    side: const BorderSide(color: Color(0x40E8C070)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: donnees.programmeActif
                      ? () => _partager(context)
                      : null,
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text('Partager'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0x24E8C070), height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              _Chiffre(
                valeur: '${donnees.filleuls}',
                libelle: donnees.filleuls > 1
                    ? 'lecteurs invités'
                    : 'lecteur invité',
              ),
              _Chiffre(
                valeur: donnees.reductionProchaine == null
                    ? '0 %'
                    : '-${donnees.reductionProchaine} %',
                libelle: 'sur le prochain abonnement',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.valeur, required this.libelle});
  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            valeur,
            style: const TextStyle(
              color: Color(0xFFF4F1E8),
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            libelle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8E99B4), fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _SectionReductions extends StatelessWidget {
  const _SectionReductions({required this.donnees});
  final CodesEtAvantages donnees;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Vos réductions', style: t.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          "Une par lecteur invité. Elles s'appliquent toutes seules, une par abonnement, "
          "et le montant réduit s'affiche avant de payer.",
          style: t.textTheme.bodySmall?.copyWith(
            color: Couleurs.grisChaud,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (donnees.bons.isEmpty)
          Text(
            'Aucune pour le moment. Partagez votre code pour en gagner.',
            style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
          ),
        for (final b in donnees.bons) _LigneBon(bon: b),
      ],
    );
  }
}

class _LigneBon extends StatelessWidget {
  const _LigneBon({required this.bon});
  final BonReduction bon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (texte, teinte) = switch (bon.statut) {
      'disponible' => (
        "Disponible jusqu'au ${_jour(bon.expireLe)}",
        Couleurs.sauge,
      ),
      'utilise' => ('Utilisée le ${_jour(bon.utiliseLe)}', Couleurs.grisChaud),
      _ => ('Expirée le ${_jour(bon.expireLe)}', Couleurs.grisChaud),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bon.nouveau
            ? Couleurs.or.withValues(alpha: 0.08)
            : t.colorScheme.surface,
        border: Border.all(
          color: bon.nouveau
              ? Couleurs.or.withValues(alpha: 0.5)
              : (t.dividerTheme.color ?? Couleurs.traitClair),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: bon.disponible
                ? Couleurs.nuit
                : t.colorScheme.surfaceContainer,
            child: Text(
              '-${bon.pourcent} %',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: bon.disponible ? Couleurs.orClair : Couleurs.grisChaud,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        bon.filleul == null
                            ? 'Un lecteur invité'
                            : 'Grâce à ${bon.filleul}',
                        style: t.textTheme.titleSmall,
                      ),
                    ),
                    if (bon.nouveau) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        color: Couleurs.or,
                        child: const Text(
                          'Nouveau',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1400),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  texte,
                  style: t.textTheme.labelSmall?.copyWith(color: teinte),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
