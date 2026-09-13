import 'package:flutter/material.dart';

/// Espace insécable : le moteur de texte ne coupe jamais la ligne à cet endroit.
const _nbsp = '\u00A0';

final _avantPonctuation = RegExp(r' ([:;?!»%])');
final _apresGuillemet = RegExp(r'« ');
final _dernierMot = RegExp(r' (\S{1,14})$');
final _paragraphe = RegExp(r'\n');
final _traitUnion = RegExp(r'(?<=\p{L})-(?=\p{L})', unicode: true);

/// Trait d'union insécable : « vingt-quatre » ne se coupe plus en fin de ligne,
/// ce qui laissait un demi-mot seul et creusait la ligne justifiée.
const _traitInsecable = '\u2011';

/// Rend un texte français plus lisible une fois coupé en lignes.
///
/// - un signe double (« : », « ? », « ! », « ; ») ou un guillemet ne commence
///   jamais une ligne ;
/// - le dernier mot d'un paragraphe ne reste jamais seul sur sa ligne : il
///   emmène le précédent avec lui ;
/// - un mot composé ne se coupe pas à son trait d'union, sauf avec [composes]
///   à faux : Fraunces n'a pas le trait d'union insécable, et un glyphe de
///   secours au milieu d'un titre se verrait plus qu'une coupure.
///
/// Seuls des caractères existants sont remplacés, un pour un, jamais ajoutés ni retirés :
/// la longueur du texte ne change pas, et une position de surlignage calculée
/// sur le texte d'origine reste juste.
String lisible(String texte, {bool composes = true}) {
  if (!texte.contains(' ')) return texte;
  return texte.split(_paragraphe).map((p) {
    var r = p
        .replaceAllMapped(_avantPonctuation, (m) => '$_nbsp${m[1]}')
        .replaceAll(_apresGuillemet, '«$_nbsp')
        .replaceAll(_traitUnion, composes ? _traitInsecable : '-');
    // Sous quatre mots, un titre court ou un libellé : rien à protéger, et
    // les coller empêcherait un bouton étroit de passer sur deux lignes.
    if (' '.allMatches(r.trim()).length >= 3) {
      r = r.trimRight().replaceFirstMapped(_dernierMot, (m) => '$_nbsp${m[1]}') +
          p.substring(p.trimRight().length);
    }
    return r;
  }).join('\n');
}

/// Le texte de l'application : un `Text` qui applique [lisible], et justifie
/// les paragraphes de lecture.
///
/// Justifier un libellé ou un titre n'apporterait rien et creuserait des
/// trous : seuls les textes de corps (police de 17 px au plus) assez longs pour
/// courir sur plusieurs lignes le sont, et seulement quand l'appelant n'a pas
/// choisi d'alignement lui-même.
class Texte extends StatelessWidget {
  const Texte(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  /// Au-delà, un texte de corps court sur plusieurs lignes dans un téléphone.
  static const seuilJustification = 90;

  /// Sans césure, une ligne justifiée de moins de 45 signes se creuse de
  /// trous : on ne justifie que si la ligne en porte assez.
  static const signesMinimum = 45;

  static TextAlign? alignement(String texte, TextStyle? style, int? maxLines, {double largeur = 360}) {
    // Un texte borné en lignes est un titre ou un aperçu coupé par « … » :
    // justifié, sa dernière ligne visible s'étire en trous béants.
    if (texte.length < seuilJustification || maxLines != null) return null;
    final taille = style?.fontSize ?? 14;
    if (taille > 17) return null;
    // Largeur utile : l'écran moins les marges habituelles des pages. Un signe
    // d'Inter occupe environ la moitié de la taille de police.
    final signesParLigne = (largeur - 48) / (taille * 0.52);
    return signesParLigne >= signesMinimum ? TextAlign.justify : null;
  }

  @override
  Widget build(BuildContext context) {
    final effectif = DefaultTextStyle.of(context).style.merge(style);
    final fraunces = effectif.fontFamily?.contains('Fraunces') ?? false;
    final rendu = lisible(data, composes: !fraunces);
    return Text(
      rendu,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign ?? alignement(data, effectif, maxLines, largeur: MediaQuery.maybeSizeOf(context)?.width ?? 360),
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel ?? (rendu == data ? null : data),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
