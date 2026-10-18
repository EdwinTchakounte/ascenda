import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../etat/session.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import '../widgets/ui.dart';

/// Retrouver son mot de passe, en deux temps sur un seul écran.
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
      body: FondPapier(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Form(
              key: _formulaire,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // L'écran se pose bloc par bloc, une fois, à l'ouverture.
                  Apparition(
                    child: _EnTete(
                      icone: _codeDemande ? Icone.encrier : Icone.clef,
                      etape: _codeDemande ? 2 : 1,
                      titre: _codeDemande ? 'Votre code est parti' : 'Retrouver votre accès',
                      texte: _codeDemande
                          ? "Si un compte existe à cette adresse, un code à six chiffres "
                              "vient d'y être envoyé. Il est valable trente minutes."
                          : "Indiquez l'adresse de votre compte. Nous y envoyons un code "
                              "à six chiffres.",
                    ),
                  ),
                  const SizedBox(height: 28),

                  Apparition(
                    rang: 1,
                    child: TextFormField(
                      controller: _email,
                      enabled: !_codeDemande,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Adresse électronique',
                        prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                      ),
                    ),
                  ),

                  if (_codeDemande) ...[
                    const SizedBox(height: 18),
                    // Le code se recopie d'un courriel : les six chiffres sont
                    // espacés au centre d'un cadre, comme sur un bon.
                    Container(
                      decoration: BoxDecoration(
                        color: p.surfaceCreuse,
                        borderRadius: Rayons.moyen,
                        border: Border.all(color: p.accentTexte.withValues(alpha: 0.35)),
                      ),
                      child: TextFormField(
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
                          hintText: '000000',
                          hintStyle: t.textTheme.headlineSmall?.copyWith(
                            letterSpacing: 10,
                            color: p.attenue.withValues(alpha: 0.6),
                          ),
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                        ),
                        validator: (v) {
                          final chiffres = (v ?? '').replaceAll(RegExp(r'\D'), '');
                          if (chiffres.length != 6) return 'Le code compte six chiffres.';
                          return null;
                        },
                      ),
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
                          IconeAscenda(Icone.question, taille: 18, couleur: p.attenue),
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
      // Le serveur ferme toutes les sessions, celle-ci comprise.
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
      body: FondPapier(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Form(
              key: _formulaire,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Apparition(
                    child: _EnTete(
                      icone: Icone.clef,
                      titre: 'Changer votre mot de passe',
                      texte: "Toutes vos sessions seront fermées, sur cet appareil comme sur "
                          "les autres. C'est ce qu'on attend quand on change un mot de "
                          "passe qu'on croit compromis.",
                    ),
                  ),
                  const SizedBox(height: 28),
                  Apparition(
                    rang: 1,
                    child: TextFormField(
                      controller: _ancien,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mot de passe actuel',
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                      ),
                      validator: (v) =>
                          (v ?? '').isEmpty ? 'Indiquez votre mot de passe actuel.' : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Apparition(
                    rang: 2,
                    child: TextFormField(
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
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 16),
                    AlerteFormulaire(_erreur!),
                  ],
                  const SizedBox(height: 26),
                  Apparition(
                    rang: 3,
                    child: FilledButton.icon(
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

/// L'en-tête d'un écran de mot de passe : l'icône tracée à la plume, l'étape
/// entre crochets, le titre en Fraunces et son explication sous un filet.
class _EnTete extends StatelessWidget {
  const _EnTete({required this.icone, required this.titre, required this.texte, this.etape});

  final Icone icone;
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
        EtiquetteCrochet(etape == null ? 'votre compte' : 'étape $etape sur 2'),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconeAscenda(icone, taille: 34, couleur: p.accentTexte),
            const SizedBox(width: 16),
            Expanded(
              child: Texte(
                titre,
                style: t.textTheme.headlineSmall?.copyWith(fontSize: 24, height: 1.15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Filet(redouble: true),
        const SizedBox(height: 14),
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
                    height: 3,
                    color: i <= etape! ? p.accent : p.surfaceCreuse,
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

