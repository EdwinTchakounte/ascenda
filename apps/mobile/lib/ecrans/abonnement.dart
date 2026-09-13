import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/libelles.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';

/// L'abonnement Ascension, du choix de la formule à la confirmation.
///
/// Le paiement passe par Tara, qui porte MTN Mobile Money et Orange Money.
/// L'application ne voit jamais le code secret du membre : elle envoie le
/// numéro, Tara pousse la demande sur le téléphone, le membre valide avec son
/// code sur son propre appareil. C'est dit à l'écran, parce que la fraude au
/// mobile money commence presque toujours par quelqu'un qui réclame ce code.
class EcranAbonnement extends ConsumerStatefulWidget {
  const EcranAbonnement({super.key});

  @override
  ConsumerState<EcranAbonnement> createState() => _EcranAbonnementState();
}

class _EcranAbonnementState extends ConsumerState<EcranAbonnement> {
  final _telephone = TextEditingController();
  final _formulaire = GlobalKey<FormState>();

  int? _periode;
  String? _reseau;
  bool _envoi = false;

  /// Le paiement en cours de validation. Tant qu'il est là, l'écran montre
  /// l'attente et non le formulaire.
  Paiement? _encours;
  Timer? _sondage;
  int _secondes = 0;

  /// Au delà, on cesse d'interroger et on laisse la main. Le paiement n'est pas
  /// perdu pour autant : la réconciliation du serveur le rattrape.
  static const _limiteAttente = 180;

  @override
  void dispose() {
    _sondage?.cancel();
    _telephone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grille = ref.watch(tarifsProvider);
    final abonnement = ref.watch(abonnementProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ascension')),
      body: SafeArea(
        bottom: false,
        child: grille.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: SqueletteCarte(lignes: 5),
          ),
          error: (e, _) => EtatErreur(
            erreur: e,
            reessayer: () => ref.invalidate(tarifsProvider),
          ),
          data: (g) => _encours != null
              ? _Attente(
                  paiement: _encours!,
                  secondes: _secondes,
                  limite: _limiteAttente,
                  onFermer: _abandonnerAttente,
                )
              : _formulaireAchat(g, abonnement.valueOrNull),
        ),
      ),
    );
  }

  Widget _formulaireAchat(Tarifs g, Abonnement? a) {
    final t = Theme.of(context);
    final formules = g.formules;
    if (formules.isEmpty) {
      return const EtatMessage(
        icone: Icons.receipt_long_outlined,
        titre: 'Aucune formule',
        texte: "La grille tarifaire n'est pas disponible pour le moment. "
            "Réessayez dans un instant.",
      );
    }
    final mensuelle = g.mensuel ?? formules.first;
    final choisie = formules.firstWhere(
      (f) => f.periodeMois == (_periode ?? formules.first.periodeMois),
      orElse: () => formules.first,
    );

    return Form(
      key: _formulaire,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          if (a != null && a.actif) _CarteEnCours(abonnement: a),
          Text(
            a != null && a.actif ? 'Prolonger votre accès' : 'Ce que change Ascension',
            style: t.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const _Avantages(),
          const SizedBox(height: 20),
          const _Comparaison(),
          const SizedBox(height: 26),

          Text('Votre formule', style: t.textTheme.titleLarge),
          const SizedBox(height: 10),
          if (g.reductionPourcent != null) _AvisReduction(tarifs: g),
          for (final f in formules)
            _CarteFormuleChoix(
              formule: f,
              mensuelle: mensuelle,
              choisie: f.periodeMois == choisie.periodeMois,
              onTap: () => setState(() => _periode = f.periodeMois),
            ),
          const SizedBox(height: 26),

          Text('Votre opérateur', style: t.textTheme.titleLarge),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final m in g.moyens) ...[
                Expanded(
                  child: _CarteOperateur(
                    moyen: m,
                    choisi: _reseau == m.reseau,
                    onTap: () => setState(() => _reseau = m.reseau),
                  ),
                ),
                if (m != g.moyens.last) const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 20),

          TextFormField(
            controller: _telephone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              LengthLimitingTextInputFormatter(14),
            ],
            decoration: const InputDecoration(
              labelText: 'Numéro mobile money',
              prefixText: '+237 ',
              hintText: '6 XX XX XX XX',
              helperText: 'Le numéro qui porte le compte, pas celui du téléphone.',
            ),
            validator: _validerTelephone,
          ),
          const SizedBox(height: 18),

          const _AvisCodeSecret(),
          const SizedBox(height: 20),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _envoi ? null : () => _payer(choisie),
              child: _envoi
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text('Payer ${choisie.montantDuLisible}'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Le paiement est tracé de bout en bout. Si la confirmation tarde, "
            "elle est rattrapée automatiquement dans les vingt-quatre heures et "
            "votre accès s'ouvre sans nouvelle démarche.",
            style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud, height: 1.6),
          ),
          const SizedBox(height: 28),
          const _Historique(),
        ],
      ),
    );
  }

  String? _validerTelephone(String? v) {
    final chiffres = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (chiffres.isEmpty) return 'Entrez le numéro qui porte votre compte mobile money.';
    final local = chiffres.startsWith('237') ? chiffres.substring(3) : chiffres;
    if (local.length != 9) return 'Un numéro camerounais compte neuf chiffres.';
    if (!local.startsWith('6')) return 'Les numéros mobiles commencent par 6.';
    return null;
  }

  Future<void> _payer(Formule f) async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    if (_reseau == null) {
      _dire('Choisissez MTN ou Orange avant de payer.');
      return;
    }
    setState(() => _envoi = true);
    try {
      final j = await ref.read(clientApiProvider).post('/paiements', corps: {
        'periode_mois': f.periodeMois,
        'telephone': _telephone.text.replaceAll(RegExp(r'\D'), ''),
        'reseau': _reseau,
      }) as Map<String, dynamic>;
      final p = Paiement.depuisJson(j);
      if (!mounted) return;
      setState(() {
        _encours = p;
        _secondes = 0;
        _envoi = false;
      });
      // Un paiement déjà validé (formule offerte, ou validation immédiate en
      // environnement de test) n'a rien à attendre.
      if (p.valide) {
        await _conclure();
      } else {
        _lancerSondage(p.id);
      }
    } on ErreurApi catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _dire(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _dire("La demande n'a pas pu partir. Vérifiez votre connexion.");
    }
  }

  void _lancerSondage(String id) {
    _sondage?.cancel();
    _sondage = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondes += 3);
      if (_secondes >= _limiteAttente) {
        timer.cancel();
        return;
      }
      try {
        final j = await ref.read(clientApiProvider).get('/paiements/$id')
            as Map<String, dynamic>;
        final p = Paiement.depuisJson(j);
        if (!mounted) return;
        setState(() => _encours = p);
        if (p.valide) {
          timer.cancel();
          await _conclure();
        } else if (p.rejete) {
          timer.cancel();
        }
      } catch (_) {
        // Une interrogation qui échoue n'arrête rien : le réseau mobile coupe
        // souvent quelques secondes, et le paiement suit son cours au serveur.
      }
    });
  }

  /// Le paiement est passé : on rafraîchit ce qui dépend du plan pour que
  /// l'application cesse immédiatement de proposer d'acheter.
  Future<void> _conclure() async {
    await ref.read(sessionProvider.notifier).rafraichirUtilisateur();
    ref.invalidate(abonnementProvider);
    ref.invalidate(paiementsProvider);
    ref.invalidate(compteProvider);
    ref.invalidate(usageProvider);
  }

  void _abandonnerAttente() {
    _sondage?.cancel();
    final valide = _encours?.valide ?? false;
    setState(() {
      _encours = null;
      _secondes = 0;
    });
    ref.invalidate(abonnementProvider);
    ref.invalidate(paiementsProvider);
    if (valide && mounted) Navigator.of(context).maybePop();
  }

  void _dire(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Avantages extends StatelessWidget {
  const _Avantages();

  static const _lignes = [
    (Icons.auto_stories_outlined, 'Les 78 ouvrages, sans plafond de citation sur ceux qui le permettent'),
    (Icons.hub_outlined, 'Tous les axes, et autant de chronogrammes que vous voulez'),
    (Icons.event_repeat_outlined, 'La replanification quand la semaine ne se passe pas comme prévu'),
    (Icons.forum_outlined, "L'agent sans limite de questions, sources et pages à l'appui"),
    (Icons.download_for_offline_outlined, 'Le pack hors ligne et les exports PDF'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        for (final (icone, texte) in _lignes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icone, size: 19, color: Couleurs.orTexte),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(texte, style: t.textTheme.bodyMedium?.copyWith(height: 1.5)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ce qui change, compteur par compteur, lu au serveur.
///
/// Les cinq lignes d'avantages au dessus sont notre argumentaire. Ce tableau
/// est la promesse chiffrée, et il vient des mêmes tables que celles qui
/// appliquent les limites : personne ne peut y lire autre chose que ce qui
/// sera réellement accordé.
class _Comparaison extends ConsumerWidget {
  const _Comparaison();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final formules = ref.watch(formulesProvider).valueOrNull;
    if (formules == null || formules.length < 2) return const SizedBox.shrink();

    Map<String, dynamic>? parCode(String code) {
      for (final f in formules) {
        if (f['code'] == code) return f;
      }
      return null;
    }

    final gratuit = parCode('free');
    final paye = parCode('premium');
    if (gratuit == null || paye == null) return const SizedBox.shrink();

    int? limite(Map<String, dynamic> f, String type) {
      for (final l in (f['limites'] as List? ?? [])) {
        if (l['type'] == type) return l['limite'] as int?;
      }
      return null;
    }

    // On ne montre que les compteurs qui changent : afficher une ligne
    // identique des deux côtés fait douter qu'il y ait une différence.
    final types = <String>[];
    for (final l in (paye['limites'] as List? ?? [])) {
      final code = '${l['type']}';
      if (limite(gratuit, code) != limite(paye, code)) types.add(code);
    }
    if (types.isEmpty) return const SizedBox.shrink();

    String periode(String type) {
      for (final l in (paye['limites'] as List? ?? [])) {
        if (l['type'] == type) return periodeQuota('${l['periode']}');
      }
      return '';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Couleurs.ivoireCreuse,
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 78,
                child: Text('${gratuit['nom']}',
                    textAlign: TextAlign.end,
                    style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
              ),
              SizedBox(
                width: 78,
                child: Text('${paye['nom']}',
                    textAlign: TextAlign.end,
                    style: t.textTheme.labelSmall?.copyWith(color: Couleurs.orTexte)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final type in types)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${libelleQuota(type)}, ${periode(type)}',
                      style: t.textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
                  SizedBox(
                    width: 78,
                    child: Text(valeurQuota(limite(gratuit, type)),
                        textAlign: TextAlign.end,
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: Couleurs.grisChaud)),
                  ),
                  SizedBox(
                    width: 78,
                    child: Text(valeurQuota(limite(paye, type)),
                        textAlign: TextAlign.end,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: Couleurs.orTexte,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CarteEnCours extends StatelessWidget {
  const _CarteEnCours({required this.abonnement});
  final Abonnement abonnement;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final j = abonnement.joursRestants;
    final fin = abonnement.fin;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Couleurs.nuit, Couleurs.ardoise]),
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: Couleurs.orClair, size: 22),
              const SizedBox(width: 10),
              Text('Ascension active',
                  style: t.textTheme.titleMedium?.copyWith(color: const Color(0xFFF4F1E8))),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            j == null
                ? 'Votre accès est ouvert.'
                : (j == 0
                    ? "Votre accès se referme aujourd'hui."
                    : "Il vous reste $j jour${j > 1 ? 's' : ''}."),
            style: t.textTheme.bodyMedium?.copyWith(
              color: abonnement.bientotEchu ? Couleurs.orClair : const Color(0xFFB9C1D6),
            ),
          ),
          if (fin != null) ...[
            const SizedBox(height: 4),
            Text(
              'Échéance le ${fin.day.toString().padLeft(2, '0')}/'
              '${fin.month.toString().padLeft(2, '0')}/${fin.year}.',
              style: t.textTheme.bodySmall?.copyWith(color: const Color(0xFF8E99B4)),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Payer maintenant ajoute la nouvelle période à celle qui reste. '
            'Vous ne perdez aucun jour.',
            style: t.textTheme.bodySmall
                ?.copyWith(color: const Color(0xFF8E99B4), height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// La réduction ambassadeur, dite avant le choix de la formule : le montant
/// barré ne doit pas surprendre, il doit s'expliquer.
class _AvisReduction extends StatelessWidget {
  const _AvisReduction({required this.tarifs});
  final Tarifs tarifs;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fin = tarifs.reductionExpire;
    return Container(
      key: const Key('avis-reduction'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Couleurs.sauge.withValues(alpha: 0.14),
        border: Border.all(color: Couleurs.sauge.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.volunteer_activism_outlined, size: 19, color: Color(0xFF476A4E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '-${tarifs.reductionPourcent} % grâce à votre code ambassadeur, '
              'appliqués à ce paiement'
              '${fin == null ? '' : " (valable jusqu'au ${fin.day}/${fin.month.toString().padLeft(2, '0')}/${fin.year})"}.',
              style: t.textTheme.bodySmall?.copyWith(color: const Color(0xFF355239), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteFormuleChoix extends StatelessWidget {
  const _CarteFormuleChoix({
    required this.formule,
    required this.mensuelle,
    required this.choisie,
    required this.onTap,
  });

  final Formule formule;
  final Formule mensuelle;
  final bool choisie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final economie = formule.economieContre(mensuelle);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: choisie ? Couleurs.or.withValues(alpha: 0.10) : t.colorScheme.surface,
        borderRadius: BorderRadius.zero,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.zero,
              border: Border.all(
                color: choisie ? Couleurs.or : Couleurs.traitClair,
                width: choisie ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  choisie ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 21,
                  color: choisie ? Couleurs.orTexte : Couleurs.grisChaud,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              formule.libelle.isEmpty
                                  ? '${formule.periodeMois} mois'
                                  : formule.libelle,
                              style: t.textTheme.titleSmall,
                            ),
                          ),
                          if (economie > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Couleurs.sauge.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Text(
                                '-$economie %',
                                style: t.textTheme.labelSmall
                                    ?.copyWith(color: const Color(0xFF476A4E)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formule.parMoisLisible} par mois',
                        style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (formule.montantReduit != null)
                      Text(
                        formule.montantLisible,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: Couleurs.grisChaud,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    Text(
                      formule.montantDuLisible,
                      style: t.textTheme.titleMedium?.copyWith(color: Couleurs.orTexte),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CarteOperateur extends StatelessWidget {
  const _CarteOperateur({required this.moyen, required this.choisi, required this.onTap});

  final MoyenPaiement moyen;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // MTN est jaune, Orange est orange : reprendre ces teintes évite au membre
    // de chercher lequel des deux il tient en main.
    final teinte = moyen.code == 'mtn' ? const Color(0xFFFFCC00) : const Color(0xFFFF6600);
    return Material(
      color: choisi ? teinte.withValues(alpha: 0.12) : t.colorScheme.surface,
      borderRadius: BorderRadius.zero,
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: choisi ? teinte : Couleurs.traitClair,
              width: choisi ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: teinte, borderRadius: BorderRadius.zero),
                child: Center(
                  child: Text(
                    moyen.code == 'mtn' ? 'MTN' : 'OM',
                    style: t.textTheme.labelSmall?.copyWith(
                      color: moyen.code == 'mtn' ? Couleurs.encre : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(moyen.libelle, style: t.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                moyen.operateur,
                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le seul message de l'écran qui parle de sécurité, et il parle d'une seule
/// chose : personne ne doit jamais demander le code mobile money.
class _AvisCodeSecret extends StatelessWidget {
  const _AvisCodeSecret();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Couleurs.ivoireCreuse,
        borderRadius: BorderRadius.zero,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 19, color: Couleurs.grisChaud),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "ASCENDA ne vous demandera jamais votre code secret. La demande "
              "arrive sur votre téléphone et vous la validez vous-même.",
              style: t.textTheme.bodySmall?.copyWith(height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// L'écran d'attente. Il montre le temps écoulé, parce qu'une attente sans
/// repère paraît deux fois plus longue et pousse à payer une seconde fois.
class _Attente extends StatelessWidget {
  const _Attente({
    required this.paiement,
    required this.secondes,
    required this.limite,
    required this.onFermer,
  });

  final Paiement paiement;
  final int secondes;
  final int limite;
  final VoidCallback onFermer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final expire = secondes >= limite && paiement.enAttente;

    final (icone, teinte, titre) = paiement.valide
        ? (Icons.check_circle_rounded, Couleurs.sauge, 'Paiement confirmé')
        : paiement.rejete
            ? (Icons.cancel_outlined, Couleurs.terracotta, "Paiement non abouti")
            : expire
                ? (Icons.schedule_rounded, Couleurs.or, 'Confirmation en attente')
                : (Icons.smartphone_rounded, Couleurs.or, 'Validez sur votre téléphone');

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: teinte.withValues(alpha: 0.14),
              shape: BoxShape.rectangle,
            ),
            child: Icon(icone, size: 40, color: teinte),
          ),
        ),
        const SizedBox(height: 22),
        Text(titre, textAlign: TextAlign.center, style: t.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          expire
              ? "La confirmation n'est pas encore arrivée. Votre paiement n'est "
                  "pas perdu : le serveur le rattrape automatiquement et votre "
                  "accès s'ouvrira dès qu'il sera confirmé."
              : paiement.message,
          textAlign: TextAlign.center,
          style: t.textTheme.bodyMedium?.copyWith(height: 1.6, color: Couleurs.grisChaud),
        ),
        const SizedBox(height: 26),
        if (paiement.enAttente && !expire) ...[
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              '${secondes ~/ 60} min ${(secondes % 60).toString().padLeft(2, '0')} s',
              style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
            ),
          ),
        ],
        const SizedBox(height: 26),
        _LigneRecu('Montant', paiement.montantLisible),
        if (paiement.reductionPourcent != null)
          _LigneRecu('Réduction ambassadeur', '-${paiement.reductionPourcent} %'),
        _LigneRecu('Durée', '${paiement.periodeMois} mois'),
        if (paiement.telephone != null) _LigneRecu('Numéro', '+${paiement.telephone}'),
        if (paiement.reseau != null) _LigneRecu('Opérateur', paiement.reseau!),
        _LigneRecu('Référence', paiement.id.substring(0, 8)),
        const SizedBox(height: 30),
        SizedBox(
          height: 50,
          child: paiement.valide
              ? FilledButton(onPressed: onFermer, child: const Text('Commencer'))
              : OutlinedButton(
                  onPressed: onFermer,
                  child: Text(paiement.rejete ? 'Réessayer' : 'Fermer'),
                ),
        ),
      ],
    );
  }
}

class _LigneRecu extends StatelessWidget {
  const _LigneRecu(this.libelle, this.valeur);
  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(libelle, style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: t.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Historique extends ConsumerWidget {
  const _Historique();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final paiements = ref.watch(paiementsProvider);
    return paiements.maybeWhen(
      data: (liste) {
        if (liste.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vos paiements', style: t.textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final p in liste.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      p.valide
                          ? Icons.check_circle_outline_rounded
                          : (p.rejete ? Icons.cancel_outlined : Icons.schedule_rounded),
                      size: 19,
                      color: p.valide
                          ? Couleurs.sauge
                          : (p.rejete ? Couleurs.terracotta : Couleurs.grisChaud),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p.periodeMois} mois', style: t.textTheme.bodyMedium),
                          if (p.creeLe != null)
                            Text(
                              '${p.creeLe!.day.toString().padLeft(2, '0')}/'
                              '${p.creeLe!.month.toString().padLeft(2, '0')}/${p.creeLe!.year}',
                              style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                            ),
                        ],
                      ),
                    ),
                    Text(p.montantLisible, style: t.textTheme.bodyMedium),
                  ],
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
