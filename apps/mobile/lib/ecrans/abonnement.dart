import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/libelles.dart';
import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../widgets/etats.dart';
import '../widgets/illustrations.dart';
import '../theme/texte.dart';
import '../widgets/ui.dart';

class EcranAbonnement extends ConsumerStatefulWidget {
  const EcranAbonnement({super.key});

  @override
  ConsumerState<EcranAbonnement> createState() => _EcranAbonnementState();
}

class _EcranAbonnementState extends ConsumerState<EcranAbonnement> {
  final _telephone = TextEditingController();
  final _formulaire = GlobalKey<FormState>();

  int? _periode;
  bool _envoi = false;

  Paiement? _encours;
  Timer? _sondage;
  int _secondes = 0;

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
      appBar: AppBar(title: const Texte('Ascension')),
      body: FondPapier(
        child: SafeArea(
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
      ),
    );
  }

  Widget _formulaireAchat(Tarifs g, Abonnement? a) {
    final t = Theme.of(context);
    final p = context.palette;
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
          Apparition(
            child: _CarteOffre(abonnement: a != null && a.actif ? a : null, formules: formules),
          ),
          const SizedBox(height: 26),
          const Apparition(rang: 1, child: TitreSection("Ce qui s'ouvre avec Ascension")),
          const SizedBox(height: 12),
          const Apparition(rang: 1, child: _Avantages()),
          const SizedBox(height: 12),
          const Apparition(rang: 2, child: _Comparaison()),
          const SizedBox(height: 28),

          const Apparition(rang: 3, child: TitreSection('Votre formule')),
          const SizedBox(height: 12),
          if (g.reductionPourcent != null) Apparition(rang: 3, child: _AvisReduction(tarifs: g)),
          for (final f in formules)
            Apparition(
              rang: 3,
              child: _CarteFormuleChoix(
                formule: f,
                mensuelle: mensuelle,
                choisie: f.periodeMois == choisie.periodeMois,
                onTap: () => setState(() => _periode = f.periodeMois),
              ),
            ),
          const SizedBox(height: 18),

          const Apparition(rang: 4, child: TitreSection('Votre paiement')),
          const SizedBox(height: 12),
          const Apparition(rang: 4, child: _BandeauTara()),
          const SizedBox(height: 16),

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
              prefixIcon: Icon(Icons.smartphone_rounded, size: 20),
              hintText: '6 XX XX XX XX',
              helperText: 'Le numéro qui porte le compte, pas celui du téléphone.',
              helperMaxLines: 2,
            ),
            validator: _validerTelephone,
          ),
          const SizedBox(height: 16),

          const _AvisCodeSecret(),
          const SizedBox(height: 20),

          SizedBox(
            height: 58,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: const RoundedRectangleBorder(borderRadius: Rayons.carte),
              ),
              onPressed: _envoi ? null : () => _payer(choisie),
              child: _envoi
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_rounded, size: 18),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Texte(
                            'Payer ${choisie.montantDuLisible}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: IconeAscenda(Icone.sceau, taille: 16, couleur: p.succes),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Texte(
                  "Le paiement est tracé de bout en bout. Si la confirmation tarde, "
                  "elle est rattrapée automatiquement dans les vingt-quatre heures et "
                  "votre accès s'ouvre sans nouvelle démarche.",
                  style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const Fleuron(),
          const SizedBox(height: 26),
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
    setState(() => _envoi = true);
    try {
      final j = await ref.read(clientApiProvider).post('/paiements', corps: {
        'periode_mois': f.periodeMois,
        'telephone': _telephone.text.replaceAll(RegExp(r'\D'), ''),
      }) as Map<String, dynamic>;
      final p = Paiement.depuisJson(j);
      if (!mounted) return;
      setState(() {
        _encours = p;
        _secondes = 0;
        _envoi = false;
      });
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
      }
    });
  }

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
      ..showSnackBar(SnackBar(content: Texte(message)));
  }
}

class _CarteOffre extends StatelessWidget {
  const _CarteOffre({required this.abonnement, required this.formules});

  final Abonnement? abonnement;
  final List<Formule> formules;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final a = abonnement;
    final meilleure = formules.reduce((x, y) => y.parMois < x.parMois ? y : x);
    return SurfaceHeros(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EtiquetteCrochet('ascension', couleur: p.accentSurHeros),
              const Spacer(),
              if (a != null)
                Pastille('Accès ouvert', icone: Icons.check_rounded, couleur: p.accentSurHeros),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconeAscenda(Icone.sceau, taille: 40, couleur: p.accentSurHeros),
              const SizedBox(width: 16),
              Expanded(
                child: Texte(
                  a != null ? 'Prolonger votre accès' : 'Ce que change Ascension',
                  style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 25, height: 1.15),
                ),
              ),
            ],
          ),
          if (a == null && meilleure.parMois > 0) ...[
            const SizedBox(height: 16),
            Filet(redouble: true, couleur: p.surHeros.withValues(alpha: 0.22)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: p.surHeros.withValues(alpha: 0.06),
                borderRadius: Rayons.moyen,
                border: Border.all(color: p.accentSurHeros.withValues(alpha: 0.32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (formules.length > 1)
                    Surtitre('À partir de', couleur: p.surHerosDoux),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 6,
                    children: [
                      Texte(
                        meilleure.parMoisLisible,
                        style: t.textTheme.headlineMedium?.copyWith(color: p.accentSurHeros, fontSize: 32),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Texte(
                          'par mois',
                          style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (a != null) ...[
            const SizedBox(height: 16),
            _EtatAbonnement(abonnement: a),
          ],
        ],
      ),
    );
  }
}

class _EtatAbonnement extends StatelessWidget {
  const _EtatAbonnement({required this.abonnement});

  final Abonnement abonnement;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final j = abonnement.joursRestants;
    final fin = abonnement.fin;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surHeros.withValues(alpha: 0.07),
        borderRadius: Rayons.carte,
        border: Border.all(color: p.surHeros.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconeAscenda(
                abonnement.bientotEchu ? Icone.soleil : Icone.signet,
                taille: 18,
                couleur: abonnement.bientotEchu ? p.accentSurHeros : p.surHeros,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Texte(
                  j == null
                      ? 'Votre accès est ouvert.'
                      : (j == 0
                          ? "Votre accès se referme aujourd'hui."
                          : "Il vous reste $j jour${j > 1 ? 's' : ''}."),
                  style: t.textTheme.titleSmall?.copyWith(
                    color: abonnement.bientotEchu ? p.accentSurHeros : p.surHeros,
                  ),
                ),
              ),
            ],
          ),
          if (fin != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Texte(
                'Échéance le ${fin.day.toString().padLeft(2, '0')}/'
                '${fin.month.toString().padLeft(2, '0')}/${fin.year}.',
                style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Texte(
            'Payer maintenant ajoute la nouvelle période à celle qui reste. '
            'Vous ne perdez aucun jour.',
            style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Avantages extends StatelessWidget {
  const _Avantages();

  static const _lignes = [
    (Icone.volumes, 'Les 78 ouvrages, sans plafond de citation sur ceux qui le permettent'),
    (Icone.boussole, 'Tous les axes, et autant de chronogrammes que vous voulez'),
    (Icone.cahier, 'La replanification quand la semaine ne se passe pas comme prévu'),
    (Icone.plume, "L'agent sans limite de questions, sources et pages à l'appui"),
    (Icone.signet, 'Le pack hors ligne et les exports PDF'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _lignes.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 11),
              const Padding(padding: EdgeInsets.only(left: 38), child: Filet()),
              const SizedBox(height: 11),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: IconeAscenda(_lignes[i].$1, taille: 22, couleur: p.accentTexte),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Texte(
                    _lignes[i].$2,
                    style: t.textTheme.bodyMedium?.copyWith(color: p.encre, height: 1.45),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Comparaison extends ConsumerWidget {
  const _Comparaison();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
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

    const colonne = 78.0;
    return Surface(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            right: 8,
            width: colonne,
            child: DecoratedBox(
              decoration: BoxDecoration(color: p.accentVoile, borderRadius: Rayons.moyen),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    const Spacer(),
                    SizedBox(
                      width: colonne,
                      child: Texte('${gratuit['nom']}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelSmall?.copyWith(color: p.attenue)),
                    ),
                    SizedBox(
                      width: colonne,
                      child: Texte('${paye['nom']}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelSmall?.copyWith(
                            color: p.accentTexte,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (var i = 0; i < types.length; i++) ...[
                  if (i > 0) const Padding(
                    padding: EdgeInsets.only(right: colonne * 2),
                    child: Filet(),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Texte(
                            '${libelleQuota(types[i])}, ${periode(types[i])}',
                            style: t.textTheme.bodySmall?.copyWith(color: p.texte, height: 1.45),
                          ),
                        ),
                        SizedBox(
                          width: colonne,
                          child: Texte(valeurQuota(limite(gratuit, types[i])),
                              textAlign: TextAlign.center,
                              style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
                        ),
                        SizedBox(
                          width: colonne,
                          child: Texte(valeurQuota(limite(paye, types[i])),
                              textAlign: TextAlign.center,
                              style: t.textTheme.bodySmall?.copyWith(
                                color: p.accentTexte,
                                fontWeight: FontWeight.w700,
                              )),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisReduction extends StatelessWidget {
  const _AvisReduction({required this.tarifs});

  final Tarifs tarifs;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final fin = tarifs.reductionExpire;
    return Container(
      key: const Key('avis-reduction'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.succes.withValues(alpha: p.sombre ? 0.16 : 0.10),
        borderRadius: Rayons.carte,
        border: Border.all(color: p.succes.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          IconeAscenda(Icone.plume, taille: 24, couleur: p.succes),
          const SizedBox(width: 14),
          Expanded(
            child: Texte(
              '-${tarifs.reductionPourcent} % grâce à votre code ambassadeur, '
              'appliqués à ce paiement'
              '${fin == null ? '' : " (valable jusqu'au ${fin.day}/${fin.month.toString().padLeft(2, '0')}/${fin.year})"}.',
              style: t.textTheme.bodySmall?.copyWith(color: p.encre, height: 1.5),
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
    final p = context.palette;
    final economie = formule.economieContre(mensuelle);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        selected: choisie,
        button: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: choisie ? Color.alphaBlend(p.accentVoile, p.surface) : p.surface,
            borderRadius: Rayons.carte,
            border: Border.all(
              color: choisie ? p.accent : p.trait,
              width: choisie ? 2 : 1,
            ),
            boxShadow: choisie
                ? [BoxShadow(color: p.accent.withValues(alpha: p.sombre ? 0.22 : 0.18), blurRadius: 22, offset: const Offset(0, 8))]
                : p.ombreCarte,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: Rayons.carte,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: choisie ? p.accent : Colors.transparent,
                        border: Border.all(
                          color: choisie ? p.accent : p.encre.withValues(alpha: 0.35),
                          width: 1.4,
                        ),
                      ),
                      child: choisie ? Icon(Icons.check_rounded, size: 16, color: p.surAccent) : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Texte(
                                formule.libelle.isEmpty
                                    ? '${formule.periodeMois} mois'
                                    : formule.libelle,
                                style: t.textTheme.titleMedium?.copyWith(color: p.encre),
                              ),
                              if (economie > 0)
                                Pastille('-$economie %', icone: Icons.trending_down_rounded, couleur: p.succes),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Texte(
                            '${formule.parMoisLisible} par mois',
                            style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (formule.montantReduit != null)
                          Texte(
                            formule.montantLisible,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: p.attenue,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        Texte(
                          formule.montantDuLisible,
                          style: t.textTheme.titleLarge?.copyWith(
                            fontSize: 19,
                            color: choisie ? p.accentTexte : p.encre,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BandeauTara extends StatelessWidget {
  const _BandeauTara();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(gradient: p.degradeHeros, borderRadius: Rayons.moyen),
            alignment: Alignment.center,
            child: IconeAscenda(Icone.jeton, taille: 24, couleur: p.accentSurHeros),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte('Tara Money', style: t.textTheme.titleSmall?.copyWith(color: p.encre)),
                const SizedBox(height: 2),
                Texte(
                  "MTN Mobile Money ou Orange Money : l'opérateur est reconnu à votre numéro.",
                  style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisCodeSecret extends StatelessWidget {
  const _AvisCodeSecret();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.surfaceCreuse,
        borderRadius: Rayons.carte,
      ),
      child: Row(
        children: [
          IconeAscenda(Icone.sceau, taille: 24, couleur: p.encre),
          const SizedBox(width: 14),
          Expanded(
            child: Texte(
              "ASCENDA ne vous demandera jamais votre code secret. La demande "
              "arrive sur votre téléphone et vous la validez vous-même.",
              style: t.textTheme.bodySmall?.copyWith(color: p.texte, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final p = context.palette;
    final expire = secondes >= limite && paiement.enAttente;

    final (scene, teinte, titre) = paiement.valide
        ? (Scene.laurier, p.succes, 'Paiement confirmé')
        : paiement.rejete
            ? (null, p.alerte, "Paiement non abouti")
            : expire
                ? (Scene.lampe, p.accentTexte, 'Confirmation en attente')
                : (Scene.lampe, p.accentTexte, 'Validez sur votre téléphone');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      children: [
        Center(
          child: scene == null
              ? Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: teinte.withValues(alpha: p.sombre ? 0.18 : 0.11),
                  ),
                  child: Icon(Icons.close_rounded, size: 42, color: teinte),
                )
              : Illustration(scene, taille: 186, accent: teinte),
        ),
        const SizedBox(height: 20),
        Center(child: EtiquetteCrochet('paiement', couleur: teinte)),
        const SizedBox(height: 14),
        Texte(titre, textAlign: TextAlign.center, style: t.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Texte(
          expire
              ? "La confirmation n'est pas encore arrivée. Votre paiement n'est "
                  "pas perdu : le serveur le rattrape automatiquement et votre "
                  "accès s'ouvrira dès qu'il sera confirmé."
              : paiement.message,
          textAlign: TextAlign.center,
          style: t.textTheme.bodyMedium?.copyWith(height: 1.6, color: p.attenue),
        ),
        const SizedBox(height: 24),
        if (paiement.enAttente && !expire) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              decoration: BoxDecoration(color: p.surfaceCreuse, borderRadius: Rayons.pilule),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: p.accent),
                  ),
                  const SizedBox(width: 10),
                  Texte(
                    '${secondes ~/ 60} min ${(secondes % 60).toString().padLeft(2, '0')} s',
                    style: t.textTheme.labelLarge?.copyWith(
                      color: p.encre,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Surface(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitreCourant('reçu', folio: paiement.id.substring(0, 8)),
              const SizedBox(height: 4),
              _LigneRecu('Montant', paiement.montantLisible),
              if (paiement.reductionPourcent != null)
                _LigneRecu('Réduction ambassadeur', '-${paiement.reductionPourcent} %'),
              _LigneRecu('Durée', '${paiement.periodeMois} mois'),
              if (paiement.telephone != null) _LigneRecu('Numéro', '+${paiement.telephone}'),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 54,
          child: paiement.valide
              ? FilledButton(onPressed: onFermer, child: const Texte('Commencer'))
              : OutlinedButton(
                  onPressed: onFermer,
                  child: Texte(paiement.rejete ? 'Réessayer' : 'Fermer'),
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
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Texte(libelle, style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
          const SizedBox(width: 12),
          Flexible(
            child: Texte(
              valeur,
              textAlign: TextAlign.right,
              style: t.textTheme.bodyMedium?.copyWith(color: p.encre, fontWeight: FontWeight.w600),
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
    final pal = context.palette;
    final paiements = ref.watch(paiementsProvider);
    return paiements.maybeWhen(
      data: (liste) {
        if (liste.isEmpty) return const SizedBox.shrink();
        final affiches = liste.take(8).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TitreSection('Vos paiements'),
            const SizedBox(height: 12),
            Surface(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < affiches.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: 10),
                      const Padding(padding: EdgeInsets.only(left: 34), child: Filet()),
                      const SizedBox(height: 10),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            affiches[i].valide
                                ? Icons.check_rounded
                                : (affiches[i].rejete ? Icons.close_rounded : Icons.schedule_rounded),
                            size: 20,
                            color: affiches[i].valide
                                ? pal.succes
                                : (affiches[i].rejete ? pal.alerte : pal.attenue),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Texte('${affiches[i].periodeMois} mois',
                                    style: t.textTheme.bodyMedium?.copyWith(color: pal.encre)),
                                if (affiches[i].creeLe != null)
                                  Texte(
                                    '${affiches[i].creeLe!.day.toString().padLeft(2, '0')}/'
                                    '${affiches[i].creeLe!.month.toString().padLeft(2, '0')}/${affiches[i].creeLe!.year}',
                                    style: t.textTheme.bodySmall?.copyWith(color: pal.attenue),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Texte(
                            affiches[i].montantLisible,
                            style: t.textTheme.bodyMedium?.copyWith(color: pal.encre, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
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
