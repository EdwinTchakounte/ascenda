#!/usr/bin/env python3
"""Le client .NET ne doit pas dériver de la mise en forme de référence.

Ce que cette suite vérifie, sans rien construire : que les jetons de couleur, les
polices et les onglets déclarés côté .NET sont ceux de l'application de référence.
Une dérive de teinte se voit ici, pas sur un écran.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from commun import Bilan  # noqa: E402

RACINE = pathlib.Path(__file__).resolve().parent.parent
FLUTTER = RACINE / "apps/mobile"
DOTNET = RACINE / "apps/mobile-dotnet/src/Ascenda.Mobile"

PALETTES = ("ivoire", "nuit", "sepia", "foret")
CHAMPS = ["fond", "surface", "surfaceCreuse", "encre", "texte", "attenue", "trait", "accent",
          "surAccent", "accentTexte", "succes", "alerte", "heros", "herosFin", "surHeros",
          "surHerosDoux", "accentSurHeros", "ombre"]


def palettes_flutter():
    source = (FLUTTER / "lib/theme/palette.dart").read_text(encoding="utf-8")
    out = {}
    for nom in PALETTES:
        bloc = re.search(rf"static const {nom} = Palette\((.*?)\n  \);", source, re.S)
        out[nom] = dict(re.findall(r"(\w+): Color\(0x([0-9A-Fa-f]{8})\)", bloc.group(1)))
    return out


def jetons_dotnet():
    source = (DOTNET / "Resources/Styles/Couleurs.xaml").read_text(encoding="utf-8")
    return dict(re.findall(r'x:Key="(\w+)">#([0-9A-Fa-f]{8})<', source))


def cle(champ, palette):
    suffixe = "" if palette == "ivoire" else palette[0].upper() + palette[1:]
    return champ[0].upper() + champ[1:] + suffixe


def main():
    b = Bilan("Portage .NET : les jetons suivent la référence")

    flutter = palettes_flutter()
    dotnet = jetons_dotnet()

    for palette in PALETTES:
        b.section(f"Palette {palette}")
        manquants, ecarts = [], []
        for champ in CHAMPS:
            attendu = flutter[palette].get(champ)
            obtenu = dotnet.get(cle(champ, palette))
            if obtenu is None:
                manquants.append(champ)
            elif obtenu.upper() != attendu.upper():
                ecarts.append(f"{champ} {obtenu} au lieu de {attendu}")
        b.verifier(f"les 18 jetons de {palette} sont déclarés", not manquants,
                   ", ".join(manquants) if manquants else "")
        b.verifier(f"aucune teinte de {palette} ne dérive", not ecarts,
                   " ; ".join(ecarts[:3]) if ecarts else "")

    b.section("Typographie")
    polices = {p.name for p in (DOTNET / "Resources/Fonts").glob("*.ttf")}
    attendues = {"Inter-Regular.ttf", "Inter-SemiBold.ttf", "Fraunces-SemiBold.ttf"}
    b.verifier("les polices de la marque sont embarquées", attendues <= polices,
               ", ".join(sorted(attendues - polices)))

    styles = (DOTNET / "Resources/Styles/Styles.xaml").read_text(encoding="utf-8")
    b.verifier("les titres portent la serif de la marque", 'Value="Fraunces"' in styles)
    b.verifier("le corps porte la linéale de la marque", 'Value="Inter"' in styles)

    b.section("Navigation")
    coque = (FLUTTER / "lib/ecrans/coque.dart").read_text(encoding="utf-8")
    bloc = re.search(r"static const _onglets = \[(.*?)\];", coque, re.S)
    onglets = [a or b for a, b in
               re.findall(r"libelle: (?:'([^']+)'|\"([^\"]+)\")", bloc.group(1))]
    shell = (DOTNET / "AppShell.xaml").read_text(encoding="utf-8")
    poses = re.findall(r'<ShellContent Title="([^"]+)"', shell)
    b.verifier("les quatre onglets portent les mêmes libellés",
               onglets == [o for o in poses if o in onglets] and len(onglets) == 4,
               f"référence {onglets} · .NET {poses}")

    b.section("Couverture des écrans")
    ecrans = {p.stem for p in (FLUTTER / "lib/ecrans").glob("*.dart")} - {"coque", "demarrage"}
    pages = {p.stem.replace("Page", "").lower()
             for p in (DOTNET / "Pages").glob("*.xaml")}
    portes = sorted(pages)
    b.verifier("au moins les huit écrans du premier jet sont portés", len(pages) >= 8,
               f"{len(pages)} pages : {', '.join(portes)}")
    b.verifier("la couverture est annoncée sans l'arrondir", True,
               f"{len(pages)} pages .NET pour {len(ecrans)} écrans de référence")

    return b.verdict()


if __name__ == "__main__":
    sys.exit(main())
