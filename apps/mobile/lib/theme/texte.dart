import 'package:flutter/material.dart';

const _nbsp = '\u00A0';
final _avantPonctuation = RegExp(r' ([:;?!»%])');
final _apresGuillemet = RegExp(r'« ');
final _dernierMot = RegExp(r' (\S{1,14})$');
final _paragraphe = RegExp(r'\n');
final _traitUnion = RegExp(r'(?<=\p{L})-(?=\p{L})', unicode: true);
const _traitInsecable = '\u2011';

String lisible(String texte, {bool composes = true}) {
  if (!texte.contains(' ')) return texte;
  return texte.split(_paragraphe).map((p) {
    var r = p
        .replaceAllMapped(_avantPonctuation, (m) => '$_nbsp${m[1]}')
        .replaceAll(_apresGuillemet, '«$_nbsp')
        .replaceAll(_traitUnion, composes ? _traitInsecable : '-');
    if (' '.allMatches(r.trim()).length >= 3) {
      r = r.trimRight().replaceFirstMapped(_dernierMot, (m) => '$_nbsp${m[1]}') +
          p.substring(p.trimRight().length);
    }
    return r;
  }).join('\n');
}

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
  static const seuilJustification = 90;
  static const signesMinimum = 52;

  static TextAlign? alignement(String texte, TextStyle? style, int? maxLines, {double largeur = 360}) {
    if (texte.length < seuilJustification || maxLines != null) return null;
    final taille = style?.fontSize ?? 14;
    if (taille > 17) return null;
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
