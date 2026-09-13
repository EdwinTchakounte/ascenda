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
              Center(
                child: Image.asset(
                  'assets/marque/logo-complet.png',
                  height: 132,
                  filterQuality: FilterQuality.medium,
                  semanticLabel: 'ASCENDA, Learn. Grow. Become.',
                ),
              ),
              const Spacer(),
              // Seulement s'il y a la place : sur un petit téléphone, le
              // rayonnage pousserait les boutons hors de l'écran.
              if (MediaQuery.sizeOf(context).height >= 720) ...[
                const _Rayonnage(),
                const SizedBox(height: 34),
              ],
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

/// Un rayonnage de dos de livres, aux teintes des parcours : l'accueil dit
/// d'emblée qu'on entre dans une bibliothèque. Dessiné, pas téléchargé : rien
/// à charger, rien qui manque sans réseau.
class _Rayonnage extends StatelessWidget {
  const _Rayonnage();

  static const _dos = [
    (h: 108.0, l: 22.0, c: '04'), (h: 124.0, l: 30.0, c: '01'), (h: 96.0, l: 18.0, c: '07'),
    (h: 132.0, l: 26.0, c: '02'), (h: 114.0, l: 34.0, c: '08'), (h: 102.0, l: 20.0, c: '03'),
    (h: 128.0, l: 24.0, c: '06'), (h: 90.0, l: 28.0, c: '05'), (h: 118.0, l: 22.0, c: '09'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _dos.length; i++)
              Transform.rotate(
                // Le dernier volume penche, comme sur une vraie étagère.
                angle: i == _dos.length - 1 ? 0.14 : 0,
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: _dos[i].l,
                  height: _dos[i].h,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(Couleurs.poles[_dos[i].c]!, Colors.black, 0.18)!,
                        Couleurs.poles[_dos[i].c]!,
                        Color.lerp(Couleurs.poles[_dos[i].c]!, Colors.black, 0.25)!,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(height: 1.4, margin: const EdgeInsets.only(top: 12), color: Couleurs.orClair.withValues(alpha: 0.7)),
                      Container(height: 1.4, margin: const EdgeInsets.only(bottom: 12), color: Couleurs.orClair.withValues(alpha: 0.7)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Container(height: 6, width: 300, color: Couleurs.or.withValues(alpha: 0.85)),
      ],
    );
  }
}

class EcranConnexion extends ConsumerStatefulWidget {
  const EcranConnexion({super.key, this.connexion = false});

  /// Ouvre l'écran directement sur la connexion. Un lecteur qui touche
  /// « J'ai déjà un compte » ne doit pas arriver sur un formulaire d'inscription.
  final bool connexion;

  @override
  ConsumerState<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends ConsumerState<EcranConnexion> {
  final _formulaire = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  final _nom = TextEditingController();
  final _code = TextEditingController();

  late bool _inscription = !widget.connexion;
  bool _masque = true;
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    _nom.dispose();
    _code.dispose();
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
        final messageCode =
            await s.inscription(_email.text, _motDePasse.text, _nom.text, code: _code.text);
        if (!mounted) return;
        // Le messager survit à la navigation : le lecteur lit ce que son code
        // a ouvert en arrivant sur le diagnostic.
        if (messageCode != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(messageCode), duration: const Duration(seconds: 6)),
          );
        }
        context.go('/diagnostic');
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
                const Center(child: MarqueAscenda(taille: 56)),
                const SizedBox(height: 26),
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
                if (_inscription) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('code-inscription'),
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: "Code d'accès ou d'ambassadeur",
                      hintText: 'Facultatif',
                      helperText: "Reçu d'ASCENDA ou d'un lecteur qui vous invite",
                      prefixIcon: Icon(Icons.confirmation_number_outlined, size: 20),
                    ),
                  ),
                ],
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
