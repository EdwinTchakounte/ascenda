import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
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

String _jour(DateTime? d) => d == null
    ? 'date à confirmer'
    : '${d.day == 1 ? '1er' : d.day} ${DateFormat('MMMM y', 'fr_FR').format(d)}';

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
      await ref.read(sessionProvider.notifier).rafraichirUtilisateur();
      ref.invalidate(codesProvider);
      ref.invalidate(usageProvider);
      ref.invalidate(compteProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Texte('${j['message'] ?? 'Code activé.'}')),
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

  void _signalerVus(CodesEtAvantages c) {
    if (_vusSignales || c.nouveaux == 0) return;
    _vusSignales = true;
    ref.read(clientApiProvider).post('/codes/bons/vus').catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final donnees = ref.watch(codesProvider);
    return Scaffold(
      appBar: AppBar(title: const Texte('Codes et avantages')),
      body: FondPapier(
        child: SafeArea(
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
                color: context.palette.accent,
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
                    const SizedBox(height: 26),
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
    final p = context.palette;
    return Surface(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EtiquetteCrochet('bon à remplir'),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconeAscenda(Icone.jeton, taille: 30, couleur: p.accentTexte),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte('Activer un code',
                        style: t.textTheme.headlineSmall?.copyWith(fontSize: 21, height: 1.15)),
                    const SizedBox(height: 5),
                    Texte(
                      "Un code reçu d'ASCENDA ouvre tout ou partie d'Ascension, pour une durée donnée.",
                      style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Filet(redouble: true),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: p.surfaceCreuse,
              borderRadius: Rayons.moyen,
              border: Border.all(color: p.accentTexte.withValues(alpha: 0.35)),
            ),
            child: TextField(
              key: const Key('saisie-code'),
              controller: controleur,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              onSubmitted: (_) => onActiver(),
              style: t.textTheme.titleLarge?.copyWith(
                color: p.encre,
                fontSize: 21,
                letterSpacing: 3.4,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'VOTRE CODE',
                hintStyle: t.textTheme.titleMedium?.copyWith(
                  color: p.attenue,
                  letterSpacing: 3.4,
                  fontWeight: FontWeight.w600,
                ),
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
            ),
          ),
          if (erreur != null) ...[
            const SizedBox(height: 12),
            AlerteFormulaire(erreur!),
          ],
          const SizedBox(height: 14),
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
                  : const Texte('Activer ce code'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionAcces extends StatelessWidget {
  const _SectionAcces({required this.donnees});

  final CodesEtAvantages donnees;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final a = donnees.acces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSection('Vos accès'),
        const SizedBox(height: 12),
        if (a.source == 'abonnement')
          _LigneAcces(
            icone: Icone.sceau,
            titre: 'Abonnement Ascension',
            detail: "Tout est ouvert jusqu'au ${_jour(a.jusquAu)}.",
          ),
        if (a.source == 'lancement')
          _LigneAcces(
            icone: Icone.soleil,
            titre: 'Période de lancement',
            detail: a.jusquAu == null
                ? 'Tout ASCENDA est ouvert à tous.'
                : "Tout ASCENDA est ouvert à tous jusqu'au ${_jour(a.jusquAu)}.",
          ),
        for (final code in a.codes) ...[
          _CarteCode(code: code, donnees: donnees),
          const SizedBox(height: 12),
        ],
        if (a.source == 'aucune')
          Surface(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconeAscenda(Icone.boussole, taille: 26, couleur: p.attenue),
                const SizedBox(width: 14),
                Expanded(
                  child: Texte(
                    "Vous êtes sur l'offre Découverte. Un code ou un abonnement ouvre le reste.",
                    style: t.textTheme.bodySmall?.copyWith(color: p.texte, height: 1.5),
                  ),
                ),
              ],
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
  final Icone icone;
  final String titre;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.accentVoile,
        borderRadius: Rayons.carte,
        border: Border.all(color: p.accentTexte.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          IconeAscenda(icone, taille: 28, couleur: p.accentTexte),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte(titre, style: t.textTheme.titleSmall?.copyWith(color: p.encre)),
                const SizedBox(height: 2),
                Texte(
                  detail,
                  style: t.textTheme.bodySmall?.copyWith(color: p.texte, height: 1.5),
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
    final p = context.palette;
    final bientot = code.joursRestants <= 3;
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconeAscenda(Icone.clef, taille: 26, couleur: p.accentTexte),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte(code.libelle, style: t.textTheme.titleSmall?.copyWith(color: p.encre)),
                    const SizedBox(height: 2),
                    Texte(
                      code.complet ? 'Tout Ascension' : 'Accès limité à :',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: p.accentTexte,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: p.surfaceCreuse,
                  borderRadius: Rayons.pilule,
                  border: Border.all(color: p.trait),
                ),
                child: Texte(
                  code.code,
                  style: t.textTheme.labelSmall?.copyWith(
                    color: p.encre,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          if (!code.complet) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in code.fonctions)
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
                    decoration: BoxDecoration(
                      color: p.succes.withValues(alpha: p.sombre ? 0.16 : 0.10),
                      borderRadius: Rayons.pilule,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 15, color: p.succes),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Texte(
                            donnees.libelle(f),
                            style: t.textTheme.labelMedium?.copyWith(color: p.encre),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Filet(),
          const SizedBox(height: 10),
          Row(
            children: [
              IconeAscenda(
                bientot ? Icone.soleil : Icone.signet,
                taille: 16,
                couleur: bientot ? p.alerte : p.attenue,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Texte(
                  code.joursRestants == 0
                      ? "Se referme aujourd'hui."
                      : "Jusqu'au ${_jour(code.fin)}, encore ${code.joursRestants} jour"
                            "${code.joursRestants > 1 ? 's' : ''}.",
                  style: t.textTheme.labelSmall?.copyWith(
                    color: bientot ? p.alerte : p.attenue,
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
        ..showSnackBar(const SnackBar(content: Texte('Code copié.')));
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
            content: Texte(
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
    final p = context.palette;
    return SurfaceHeros(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EtiquetteCrochet('ambassadeur', couleur: p.accentSurHeros),
              const Spacer(),
              IconeAscenda(Icone.plume, taille: 24, couleur: p.accentSurHeros),
            ],
          ),
          const SizedBox(height: 16),
          Texte(
            'Votre code ambassadeur',
            style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 22, height: 1.15),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: p.surHeros.withValues(alpha: 0.07),
              borderRadius: Rayons.carte,
              border: Border.all(color: p.accentSurHeros.withValues(alpha: 0.45), width: 1.2),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: Rayons.moyen,
                border: Border.all(color: p.accentSurHeros.withValues(alpha: 0.22)),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SelectableText(
                    donnees.code,
                    key: const Key('code-ambassadeur'),
                    style: t.textTheme.headlineMedium?.copyWith(
                      color: p.accentSurHeros,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Texte(
            donnees.programmeActif
                ? "Chaque personne qui crée son compte avec ce code vous offre "
                      "${donnees.pourcent} % de réduction sur votre prochain abonnement, "
                      "valable ${donnees.validiteJours} jours."
                : "Le programme ambassadeur est suspendu pour le moment. Votre code reste le vôtre.",
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux, height: 1.6),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copier(context),
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Texte('Copier', maxLines: 1),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    foregroundColor: p.accentSurHeros,
                    side: BorderSide(color: p.accentSurHeros.withValues(alpha: 0.35)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: donnees.programmeActif
                      ? () => _partager(context)
                      : null,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Texte('Partager', maxLines: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Chiffre(
                  nombre: donnees.filleuls,
                  libelle: donnees.filleuls > 1
                      ? 'lecteurs invités'
                      : 'lecteur invité',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Chiffre(
                  valeur: donnees.reductionProchaine == null
                      ? '0 %'
                      : '-${donnees.reductionProchaine} %',
                  libelle: 'sur le prochain abonnement',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({this.valeur, this.nombre, required this.libelle})
      : assert(valeur != null || nombre != null);
  final String? valeur;
  final int? nombre;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final style = t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 24);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: p.surHeros.withValues(alpha: 0.06),
        borderRadius: Rayons.moyen,
      ),
      child: Column(
        children: [
          nombre != null ? CompteurAnime(nombre!, style: style) : Texte(valeur!, style: style),
          const SizedBox(height: 2),
          Texte(
            libelle,
            textAlign: TextAlign.center,
            style: t.textTheme.labelSmall?.copyWith(color: p.surHerosDoux, fontSize: 11.5),
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
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSection(
          'Vos réductions',
          sousTitre: "Une par lecteur invité. Elles s'appliquent toutes seules, une par abonnement, "
              "et le montant réduit s'affiche avant de payer.",
        ),
        const SizedBox(height: 12),
        if (donnees.bons.isEmpty)
          Surface(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
            child: Column(
              children: [
                const Illustration(Scene.graine, taille: 132),
                const SizedBox(height: 14),
                Texte(
                  'Aucune pour le moment. Partagez votre code pour en gagner.',
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium?.copyWith(color: p.attenue, height: 1.55),
                ),
              ],
            ),
          ),
        for (final b in donnees.bons) ...[
          _LigneBon(bon: b),
          const SizedBox(height: 10),
        ],
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
    final p = context.palette;
    final (texte, teinte) = switch (bon.statut) {
      'disponible' => (
        "Disponible jusqu'au ${_jour(bon.expireLe)}",
        p.succes,
      ),
      'utilise' => ('Utilisée le ${_jour(bon.utiliseLe)}', p.attenue),
      _ => ('Expirée le ${_jour(bon.expireLe)}', p.attenue),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bon.nouveau ? Color.alphaBlend(p.accentVoile, p.surface) : p.surface,
        borderRadius: Rayons.carte,
        border: Border.all(
          color: bon.nouveau ? p.accent.withValues(alpha: 0.6) : p.trait,
          width: bon.nouveau ? 1.4 : 1,
        ),
        boxShadow: p.ombreCarte,
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: bon.disponible ? p.degradeHeros : null,
              color: bon.disponible ? null : p.surfaceCreuse,
              borderRadius: Rayons.moyen,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Texte(
                  '-${bon.pourcent} %',
                  textAlign: TextAlign.center,
                  style: t.textTheme.titleMedium?.copyWith(
                    color: bon.disponible ? p.accentSurHeros : p.attenue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const _Perforation(hauteur: 52),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Texte(
                        bon.filleul == null
                            ? 'Un lecteur invité'
                            : 'Grâce à ${bon.filleul}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleSmall?.copyWith(color: p.encre),
                      ),
                    ),
                    if (bon.nouveau) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: p.accent, borderRadius: Rayons.pilule),
                        child: Texte(
                          'Nouveau',
                          style: t.textTheme.labelSmall?.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: p.surAccent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: teinte, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Texte(
                        texte,
                        style: t.textTheme.labelSmall?.copyWith(color: teinte),
                      ),
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

class _Perforation extends StatelessWidget {
  const _Perforation({required this.hauteur});

  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: 1,
      height: hauteur,
      child: CustomPaint(painter: _Pointilles(p.encre.withValues(alpha: p.sombre ? 0.30 : 0.20))),
    );
  }
}

class _Pointilles extends CustomPainter {
  _Pointilles(this.couleur);

  final Color couleur;

  @override
  void paint(Canvas canvas, Size t) {
    final pinceau = Paint()
      ..color = couleur
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var y = 0.0; y < t.height; y += 6) {
      canvas.drawLine(Offset(0.5, y), Offset(0.5, (y + 3).clamp(0, t.height)), pinceau);
    }
  }

  @override
  bool shouldRepaint(covariant _Pointilles autre) => autre.couleur != couleur;
}
