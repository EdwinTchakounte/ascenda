import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formulaire,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _codeDemande ? 'Votre code est parti' : 'Retrouver votre accès',
                  style: t.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _codeDemande
                      ? "Si un compte existe à cette adresse, un code à six chiffres "
                          "vient d'y être envoyé. Il est valable trente minutes."
                      : "Indiquez l'adresse de votre compte. Nous y envoyons un code "
                          "à six chiffres.",
                  style: t.textTheme.bodyMedium
                      ?.copyWith(color: Couleurs.grisChaud, height: 1.55),
                ),
                const SizedBox(height: 26),

                TextFormField(
                  controller: _email,
                  enabled: !_codeDemande,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Adresse électronique'),
                ),

                if (_codeDemande) ...[
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: t.textTheme.headlineSmall?.copyWith(letterSpacing: 10),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Code reçu',
                      hintText: '000000',
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
                  _Alerte(_erreur!),
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
                      : Text(_codeDemande ? 'Changer mon mot de passe' : 'Envoyer le code'),
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
                    child: const Text("Corriger l'adresse"),
                  ),
                  Text(
                    "Le code n'arrive pas ? Regardez dans les indésirables. "
                    "Un nouveau code ne peut être demandé qu'après un quart d'heure.",
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: Couleurs.grisChaud, height: 1.5),
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
            content: Text('Mot de passe changé. Reconnectez-vous.'),
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
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formulaire,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Changer votre mot de passe',
                  style: t.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  "Toutes vos sessions seront fermées, sur cet appareil comme sur "
                  "les autres. C'est ce qu'on attend quand on change un mot de "
                  "passe qu'on croit compromis.",
                  style: t.textTheme.bodyMedium
                      ?.copyWith(color: Couleurs.grisChaud, height: 1.55),
                ),
                const SizedBox(height: 26),
                TextFormField(
                  controller: _ancien,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mot de passe actuel'),
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
                  _Alerte(_erreur!),
                ],
                const SizedBox(height: 26),
                FilledButton(
                  onPressed: _envoi ? null : _valider,
                  child: _envoi
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('Changer et me déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Alerte extends StatelessWidget {
  const _Alerte(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Couleurs.terracotta.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: Couleurs.terracotta),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: t.textTheme.bodySmall
                  ?.copyWith(color: Couleurs.terracotta, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
