import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../etat/session.dart';
import '../theme/palette.dart';
import '../theme/texte.dart';
import '../widgets/ui.dart';

/// Retrouver son mot de passe, en deux temps sur un seul écran.
///
/// Un code à six chiffres plutôt qu'un lien : on lit souvent ses courriels sur
/// un autre appareil que celui où l'application tourne, et un lien profond
/// suppose un site déployé, ce que nous n'avons pas. Un code se recopie.
///
/// L'écran ne dit jamais si l'adresse existe. Le serveur répond la même chose
/// dans tous les cas, et l'interface ne doit pas trahir ce que le serveur tait.
class EcranMotDePasseOublie extends ConsumerStatefulWidget {
  const EcranMotDePasseOublie({super.key, this.email});

  /// Pré-remplie depuis l'écran de connexion, quand l'adresse y était déjà.
  final String? email;

  @override
  ConsumerState<EcranMotDePasseOublie> createState() => _EtatMotDePasseOublie();
}

class _EtatMotDePasseOublie extends ConsumerState<EcranMotDePasseOublie> {
  final _formulaire = GlobalKey<FormState>();
  late final TextEditingController _email =
      TextEditingController(text: widget.email ?? '');
  final _code = TextEditingController();
  final _nouveau = TextEditingController();

  /// Faux tant qu'on n'a pas demandé le code.
  bool _codeDemande = false;
  bool _masque = true;
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _nouveau.dispose();
    super.dispose();
  }

  Future<void> _demander() async {
    final adresse = _email.text.trim();
    if (adresse.isEmpty || !adresse.contains('@')) {
      setState(() => _erreur = 'Indiquez votre adresse électronique.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await ref.read(clientApiProvider).post(
            '/auth/mot-de-passe-oublie',
            corps: {'email': adresse},
            auth: false,
          );
      if (!mounted) return;
      setState(() => _codeDemande = true);
    } on HorsLigne {
      setState(() => _erreur = 'Pas de connexion. Vérifiez votre réseau.');
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.message);
    } catch (_) {
      setState(() => _erreur = "L'envoi n'a pas pu partir. Réessayez.");
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _reinitialiser() async {
    if (!_formulaire.currentState!.validate()) return;
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await ref.read(clientApiProvider).post(
            '/auth/mot-de-passe-reinitialiser',
            corps: {
              'email': _email.text.trim(),
              'code': _code.text.trim(),
              'nouveau': _nouveau.text,
            },
            auth: false,
          );
      if (!mounted) return;
      // On enchaîne sur la connexion : demander de ressaisir ce qu'on vient de
      // choisir, trente secondes après l'avoir choisi, n'a aucun sens.
      await ref
          .read(sessionProvider.notifier)
          .connexion(_email.text.trim(), _nouveau.text);
      if (mounted) Navigator.of(context).pop(true);
    } on HorsLigne {
      setState(() => _erreur = 'Pas de connexion. Vérifiez votre réseau.');
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.message);
    } catch (_) {
      setState(() => _erreur = "Une erreur inattendue est survenue.");
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Texte('Mot de passe oublié')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formulaire,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EnTete(
                  icone: _codeDemande ? Icons.mark_email_read_outlined : Icons.lock_reset_rounded,
                  etape: _codeDemande ? 2 : 1,
                  titre: _codeDemande ? 'Votre code est parti' : 'Retrouver votre accès',
                  texte: _codeDemande
                      ? "Si un compte existe à cette adresse, un code à six chiffres "
                          "vient d'y être envoyé. Il est valable trente minutes."
                      : "Indiquez l'adresse de votre compte. Nous y envoyons un code "
                          "à six chiffres.",
                ),
                const SizedBox(height: 28),

                TextFormField(
                  controller: _email,
                  enabled: !_codeDemande,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Adresse électronique',
                    prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                  ),
                ),

                if (_codeDemande) ...[
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: t.textTheme.headlineSmall?.copyWith(letterSpacing: 10, color: p.encre),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Code reçu',
                      hintText: '000000',
                      fillColor: p.surfaceCreuse,
                    ),
                    validator: (v) {
                      final chiffres = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      if (chiffres.length != 6) return 'Le code compte six chiffres.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nouveau,
                    obscureText: _masque,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _reinitialiser(),
                    decoration: InputDecoration(
                      labelText: 'Nouveau mot de passe',
                      helperText: 'Au moins 8 caractères',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(_masque
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _masque = !_masque),
                        tooltip: _masque ? 'Afficher' : 'Masquer',
                      ),
                    ),
                    validator: (v) {
                      if ((v ?? '').length < 8) return 'Huit caractères au minimum.';
                      return null;
                    },
                  ),
                ],

                if (_erreur != null) ...[
                  const SizedBox(height: 16),
                  AlerteFormulaire(_erreur!),
                ],

                const SizedBox(height: 26),
                FilledButton(
                  onPressed: _envoi ? null : (_codeDemande ? _reinitialiser : _demander),
                  child: _envoi
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Texte(_codeDemande ? 'Changer mon mot de passe' : 'Envoyer le code'),
                ),

                if (_codeDemande) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _envoi
                        ? null
                        : () => setState(() {
                              _codeDemande = false;
                              _code.clear();
                              _erreur = null;
                            }),
                    child: const Texte("Corriger l'adresse"),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(color: p.surfaceCreuse, borderRadius: Rayons.moyen),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: p.attenue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Texte(
                            "Le code n'arrive pas ? Regardez dans les indésirables. "
                            "Un nouveau code ne peut être demandé qu'après un quart d'heure.",
                            style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Changer son mot de passe en connaissant l'ancien, depuis le profil.
class EcranChangerMotDePasse extends ConsumerStatefulWidget {
  const EcranChangerMotDePasse({super.key});

  @override
  ConsumerState<EcranChangerMotDePasse> createState() => _EtatChangerMotDePasse();
}

class _EtatChangerMotDePasse extends ConsumerState<EcranChangerMotDePasse> {
  final _formulaire = GlobalKey<FormState>();
  final _ancien = TextEditingController();
  final _nouveau = TextEditingController();

  bool _masque = true;
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _ancien.dispose();
    _nouveau.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (!_formulaire.currentState!.validate()) return;
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await ref.read(clientApiProvider).post('/auth/mot-de-passe', corps: {
        'ancien': _ancien.text,
        'nouveau': _nouveau.text,
      });
      if (!mounted) return;
      // Le serveur ferme toutes les sessions, celle-ci comprise. Rester sur
      // place donnerait une application qui échoue à la première requête
      // suivante sans dire pourquoi.
      await ref.read(sessionProvider.notifier).deconnexion();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Texte('Mot de passe changé. Reconnectez-vous.'),
          ),
        );
      }
    } on HorsLigne {
      setState(() => _erreur = 'Pas de connexion. Vérifiez votre réseau.');
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.message);
    } catch (_) {
      setState(() => _erreur = "Une erreur inattendue est survenue.");
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Texte('Mot de passe')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formulaire,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _EnTete(
                  icone: Icons.key_rounded,
                  titre: 'Changer votre mot de passe',
                  texte: "Toutes vos sessions seront fermées, sur cet appareil comme sur "
                      "les autres. C'est ce qu'on attend quand on change un mot de "
                      "passe qu'on croit compromis.",
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _ancien,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe actuel',
                    prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Indiquez votre mot de passe actuel.' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nouveau,
                  obscureText: _masque,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _valider(),
                  decoration: InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    helperText: 'Au moins 8 caractères',
                    prefixIcon: const Icon(Icons.key_outlined, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_masque
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _masque = !_masque),
                      tooltip: _masque ? 'Afficher' : 'Masquer',
                    ),
                  ),
                  validator: (v) =>
                      (v ?? '').length < 8 ? 'Huit caractères au minimum.' : null,
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 16),
                  AlerteFormulaire(_erreur!),
                ],
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _envoi ? null : _valider,
                  icon: _envoi ? const SizedBox.shrink() : const Icon(Icons.logout_rounded, size: 19),
                  label: _envoi
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Texte('Changer et me déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// L'en-tête d'un écran de mot de passe : une grande icône sur voile doré,
/// l'étape s'il y en a, le titre en Fraunces et son explication.
class _EnTete extends StatelessWidget {
  const _EnTete({required this.icone, required this.titre, required this.texte, this.etape});

  final IconData icone;
  final String titre;
  final String texte;

  /// L'étape en cours sur deux, ou rien pour un écran en un temps.
  final int? etape;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconePastille(icone, taille: 56),
            const Spacer(),
            if (etape != null) Pastille('Étape $etape sur 2', icone: Icons.timeline_rounded),
          ],
        ),
        const SizedBox(height: 20),
        Texte(titre, style: t.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Texte(texte, style: t.textTheme.bodyMedium?.copyWith(color: p.attenue, height: 1.55)),
        if (etape != null) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 1; i <= 2; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: Rayons.pilule,
                      color: i <= etape! ? p.accent : p.surfaceCreuse,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

