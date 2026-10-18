import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import '../widgets/ui.dart';

/// La marque ASCENDA : le vrai logo, pas une approximation.
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

/// L'accueil des visiteurs.
class EcranBienvenue extends StatelessWidget {
  const EcranBienvenue({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const nuit = Palette.nuit;
    return Scaffold(
      backgroundColor: Couleurs.marqueNuit,
      body: Stack(
        children: [
          // Deux lueurs très basses : l'or du logo en haut, un bleu plus
          // profond en bas. Le fond cesse d'être un aplat sans devenir un décor.
          Positioned(
            top: -140,
            left: 0,
            right: 0,
            child: _Lueur(couleur: Couleurs.marqueOr.withValues(alpha: 0.14), taille: 420),
          ),
          Positioned(
            bottom: -160,
            left: -120,
            child: _Lueur(couleur: nuit.heros.withValues(alpha: 0.55), taille: 380),
          ),
          SafeArea(
            // Défilable : avec une grande taille de police réglée sur le
            // téléphone, les boutons ne doivent jamais sortir de l'écran.
            child: LayoutBuilder(
              builder: (context, contraintes) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: contraintes.maxHeight - 64),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // Le bloc complet porte déjà le nom et la baseline.
                        Image.asset(
                          'assets/marque/logo-complet.png',
                          height: 120,
                          filterQuality: FilterQuality.medium,
                          semanticLabel: 'ASCENDA, Learn. Grow. Become.',
                        ),
                        const Spacer(),
                        const SizedBox(height: 28),
                        if (contraintes.maxHeight >= 640) ...[
                          const _Rayonnage(),
                          const SizedBox(height: 24),
                          // Le titre courant de la couverture : petites
                          // capitales d'or, comme sur un dos de volume.
                          Texte(
                            'ATELIER DE LECTURE',
                            textAlign: TextAlign.center,
                            style: t.textTheme.labelSmall?.copyWith(
                              color: Couleurs.marqueOr.withValues(alpha: 0.75),
                              letterSpacing: 3.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 22),
                        ],
                        Texte(
                          "Lisez avec un plan à votre rythme, validez chaque chapitre par un quiz "
                          "et posez vos questions à un agent qui cite le livre et la page.",
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyLarge?.copyWith(
                            color: nuit.texte,
                            height: 1.55,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Couleurs.marqueOr,
                              foregroundColor: nuit.surAccent,
                              minimumSize: const Size.fromHeight(56),
                              shape: const RoundedRectangleBorder(borderRadius: Rayons.carte),
                            ),
                            onPressed: () => context.push('/connexion'),
                            child: const Texte('Créer mon compte'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            // Le thème clair donne une teinte encre, invisible sur
                            // ce fond de nuit : les couleurs sont posées ici.
                            style: OutlinedButton.styleFrom(
                              foregroundColor: nuit.encre,
                              backgroundColor: nuit.surHeros.withValues(alpha: 0.05),
                              side: BorderSide(color: nuit.accentSurHeros.withValues(alpha: 0.45)),
                              minimumSize: const Size.fromHeight(56),
                              shape: const RoundedRectangleBorder(borderRadius: Rayons.carte),
                            ),
                            onPressed: () => context.go('/bibliotheque'),
                            child: const Texte('Parcourir la bibliothèque'),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: nuit.accentSurHeros),
                          onPressed: () => context.push('/connexion?mode=connexion'),
                          child: const Texte("J'ai déjà un compte"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une lueur ronde qui s'efface vers ses bords.
class _Lueur extends StatelessWidget {
  const _Lueur({required this.couleur, required this.taille});
  final Color couleur;
  final double taille;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(
          child: Container(
            width: taille,
            height: taille,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [couleur, couleur.withValues(alpha: 0)]),
            ),
          ),
        ),
      );
}

/// Un rayonnage de dos de livres, aux teintes des parcours
class _Rayonnage extends StatelessWidget {
  const _Rayonnage();

  static const _dos = [
    (h: 108.0, l: 22.0, c: '04'), (h: 124.0, l: 30.0, c: '01'), (h: 96.0, l: 18.0, c: '07'),
    (h: 132.0, l: 26.0, c: '02'), (h: 114.0, l: 34.0, c: '08'), (h: 102.0, l: 20.0, c: '03'),
    (h: 128.0, l: 24.0, c: '06'), (h: 90.0, l: 28.0, c: '05'), (h: 118.0, l: 22.0, c: '09'),
  ];

  @override
  Widget build(BuildContext context) {
    const nuit = Palette.nuit;
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
                    // Des dos arrondis en tête, posés à plat sur l'étagère.
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5), bottom: Radius.circular(2)),
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
                      Container(
                        height: 1.4,
                        margin: const EdgeInsets.only(top: 12),
                        color: nuit.accentSurHeros.withValues(alpha: 0.7),
                      ),
                      Container(
                        height: 1.4,
                        margin: const EdgeInsets.only(bottom: 12),
                        color: nuit.accentSurHeros.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Container(
          height: 6,
          width: 300,
          decoration: BoxDecoration(
            borderRadius: Rayons.pilule,
            gradient: LinearGradient(
              colors: [
                Couleurs.marqueOr.withValues(alpha: 0.2),
                Couleurs.marqueOr.withValues(alpha: 0.9),
                Couleurs.marqueOr.withValues(alpha: 0.2),
              ],
            ),
          ),
        ),
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
            SnackBar(content: Texte(messageCode), duration: const Duration(seconds: 6)),
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
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/bienvenue'))),
      body: FondPapier(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Form(
              key: _formulaire,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // La marque dans son cartouche : une plaque de titre à double
                  // filet d'or, qui la pose sans la noyer quel que soit le thème.
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: p.surface,
                        border: Border.all(color: p.accentTexte.withValues(alpha: 0.40), width: 1.4),
                        boxShadow: p.ombreCarte,
                      ),
                      child: Container(
                        width: 82,
                        height: 82,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: p.accentTexte.withValues(alpha: 0.22)),
                        ),
                        child: const MarqueAscenda(taille: 54),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Column(
                      key: ValueKey(_inscription),
                      children: [
                        Center(
                          child: EtiquetteCrochet(_inscription ? 'nouveau lecteur' : 'retour au rayon'),
                        ),
                        const SizedBox(height: 14),
                        Texte(
                          _inscription ? 'Créer votre compte' : 'Content de vous revoir',
                          textAlign: TextAlign.center,
                          style: t.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Texte(
                          _inscription
                              ? "Gratuit, sans carte bancaire. Vous choisirez votre axe juste après."
                              : "Reprenez votre chronogramme là où vous l'aviez laissé.",
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyMedium?.copyWith(color: p.attenue, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Fleuron(),
                  const SizedBox(height: 22),
                  if (_inscription) ...[
                    TextFormField(
                      controller: _nom,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Votre nom',
                        hintText: 'Facultatif',
                        prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Adresse électronique',
                      prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                    ),
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
                    AlerteFormulaire(_erreur!),
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
                        : Texte(_inscription ? 'Créer mon compte' : 'Me connecter'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _envoi
                        ? null
                        : () => setState(() {
                              _inscription = !_inscription;
                              _erreur = null;
                            }),
                    child: Texte(_inscription
                        ? "J'ai déjà un compte"
                        : "Je n'ai pas encore de compte"),
                  ),
                  // Le lien n'apparaît qu'en connexion : le proposer pendant une
                  // inscription n'aurait aucun sens, il n'y a rien à retrouver.
                  if (!_inscription)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: p.attenue),
                      onPressed: _envoi
                          ? null
                          : () => context.push(
                                '/mot-de-passe-oublie?email='
                                '${Uri.encodeComponent(_email.text.trim())}',
                              ),
                      child: const Texte("J'ai oublié mon mot de passe"),
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

