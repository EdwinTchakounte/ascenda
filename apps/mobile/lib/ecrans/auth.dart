import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';

/// La marque ASCENDA : le vrai logo, pas une approximation.
///
/// Le « A » porte une comète, une étoile et une silhouette aux bras levés, avec
/// des dégradés qu'un tracé redessiné ne rendrait pas. On sert donc le fichier.
class MarqueAscenda extends StatelessWidget {
  const MarqueAscenda({super.key, this.taille = 44, this.couleur});

  final double taille;

  /// Ignorée : le logo porte ses propres couleurs. Le paramètre reste pour ne
  /// pas casser les appels existants.
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/marque/marque-512.png',
      width: taille,
      height: taille,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'ASCENDA',
    );
  }
}

class EcranBienvenue extends StatelessWidget {
  const EcranBienvenue({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: Couleurs.nuitProfond,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Le bloc complet porte déjà le nom et la baseline : les
              // réécrire à côté ferait doublon.
              Image.asset(
                'assets/marque/logo-complet.png',
                height: 132,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'ASCENDA, Learn. Grow. Become.',
              ),
              const Spacer(),
              Text(
                "Vous n'avez pas besoin\nde plus de livres.",
                style: t.textTheme.headlineLarge?.copyWith(
                  color: const Color(0xFFF7F4EC),
                  fontSize: 30,
                ),
              ),
              Text(
                "Vous avez besoin\nd'un plan.",
                style: t.textTheme.headlineLarge?.copyWith(
                  color: Couleurs.orClair,
                  fontSize: 30,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Dites où vous en êtes et combien de temps vous avez vraiment. "
                "ASCENDA découpe la bibliothèque en séances que vous pouvez tenir, et "
                "répond à vos questions en citant toujours le livre et la page.",
                style: t.textTheme.bodyMedium?.copyWith(color: const Color(0xFFB9C1D6)),
              ),
              const SizedBox(height: 34),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push('/connexion'),
                  child: const Text('Créer mon compte'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => context.go('/bibliotheque'),
                  child: const Text('Parcourir la bibliothèque'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EcranConnexion extends ConsumerStatefulWidget {
  const EcranConnexion({super.key});

  @override
  ConsumerState<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends ConsumerState<EcranConnexion> {
  final _formulaire = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  final _nom = TextEditingController();

  bool _inscription = true;
  bool _masque = true;
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    _nom.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (!_formulaire.currentState!.validate()) return;
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final s = ref.read(sessionProvider.notifier);
      if (_inscription) {
        await s.inscription(_email.text, _motDePasse.text, _nom.text);
        if (mounted) context.go('/diagnostic');
      } else {
        await s.connexion(_email.text, _motDePasse.text);
        if (mounted) context.go('/aujourdhui');
      }
    } on HorsLigne {
      setState(() => _erreur = "Pas de connexion. Vérifiez votre réseau et réessayez.");
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
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/bienvenue'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formulaire,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _inscription ? 'Créer votre compte' : 'Content de vous revoir',
                  style: t.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _inscription
                      ? "Gratuit, sans carte bancaire. Vous choisirez votre axe juste après."
                      : "Reprenez votre chronogramme là où vous l'aviez laissé.",
                  style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
                ),
                const SizedBox(height: 28),
                if (_inscription) ...[
                  TextFormField(
                    controller: _nom,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Votre nom',
                      hintText: 'Facultatif',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Adresse électronique'),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Indiquez votre adresse.';
                    if (!s.contains('@') || !s.contains('.')) {
                      return "Cette adresse ne semble pas valide.";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _motDePasse,
                  obscureText: _masque,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _valider(),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    helperText: _inscription ? 'Au moins 8 caractères' : null,
                    suffixIcon: IconButton(
                      icon: Icon(_masque
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _masque = !_masque),
                      tooltip: _masque ? 'Afficher' : 'Masquer',
                    ),
                  ),
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Indiquez un mot de passe.';
                    if (_inscription && v!.length < 8) {
                      return 'Huit caractères au minimum.';
                    }
                    return null;
                  },
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Couleurs.terracotta.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 18, color: Couleurs.terracotta),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _erreur!,
                            style: t.textTheme.bodySmall
                                ?.copyWith(color: Couleurs.terracotta, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      : Text(_inscription ? 'Créer mon compte' : 'Me connecter'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _envoi
                      ? null
                      : () => setState(() {
                            _inscription = !_inscription;
                            _erreur = null;
                          }),
                  child: Text(_inscription
                      ? "J'ai déjà un compte"
                      : "Je n'ai pas encore de compte"),
                ),
                // Le lien n'apparaît qu'en connexion : le proposer pendant une
                // inscription n'aurait aucun sens, il n'y a rien à retrouver.
                if (!_inscription)
                  TextButton(
                    onPressed: _envoi
                        ? null
                        : () => context.push(
                              '/mot-de-passe-oublie?email='
                              '${Uri.encodeComponent(_email.text.trim())}',
                            ),
                    child: const Text("J'ai oublié mon mot de passe"),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
