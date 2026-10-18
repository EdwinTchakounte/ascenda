#!/usr/bin/env python3
"""Compare au pixel les écrans des deux applications, sur l'appareil branché.

Les deux applications portent des identifiants distincts et s'installent donc
côte à côte. Ce banc ouvre le même onglet dans chacune, capture, puis mesure
l'écart : part de pixels qui diffèrent, écart moyen, et une carte qui montre où.

    ./tests/comparer_portage.py                 # les quatre onglets
    ./tests/comparer_portage.py jour quiz       # seulement ceux-là

Les images sortent dans docs/comparaison-portage/ : pour chaque écran, la
capture Flutter, la capture .NET, et la carte des différences.

Les deux moteurs ne dessinent pas le texte de la même façon : Flutter pose lui
même ses glyphes, MAUI passe par les vues d'Android. Un écart résiduel sur le
tracé des lettres est donc attendu ; ce qui doit coïncider, ce sont les teintes,
les espacements et les tailles.
"""
import pathlib
import re
import subprocess
import sys
import time

ADB = str(pathlib.Path.home() / "Android/Sdk/platform-tools/adb")
RACINE = pathlib.Path(__file__).resolve().parent.parent
SORTIE = RACINE / "docs/comparaison-portage"

FLUTTER = "com.ascenda.ascenda"
DOTNET = "com.ascenda.dotnet.recette"

ONGLETS = {
    "jour": "Le jour",
    "livres": "Les livres",
    "agent": "L'agent",
    "chemin": "Le chemin",
}

TOLERANCE = 6          # un écart de teinte sous ce seuil ne compte pas
SEUIL_ALERTE = 0.08    # au-delà, l'écran est signalé


def sh(*args, binaire=False):
    r = subprocess.run([ADB, *args], capture_output=True)
    return r.stdout if binaire else r.stdout.decode("utf-8", "ignore")


def noeuds():
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    s = sh("shell", "cat", "/sdcard/ui.xml")
    out = []
    for m in re.finditer(
        r'text="([^"]*)"[^>]*?content-desc="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', s
    ):
        t, d, x1, y1, x2, y2 = m.groups()
        if t or d:
            out.append(((t or d), (int(x1) + int(x2)) // 2, (int(y1) + int(y2)) // 2))
    return out


def toucher(fragment, pause=3.0):
    for libelle, x, y in noeuds():
        if fragment.lower() in libelle.lower():
            sh("shell", "input", "tap", str(x), str(y))
            time.sleep(pause)
            return True
    return False


def capturer(nom):
    SORTIE.mkdir(parents=True, exist_ok=True)
    f = SORTIE / f"{nom}.png"
    f.write_bytes(sh("exec-out", "screencap", "-p", binaire=True))
    return f


def ouvrir(paquet):
    sh("shell", "am", "force-stop", paquet)
    sh("shell", "monkey", "-p", paquet, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(7)


def comparer(a, b, nom):
    from PIL import Image, ImageChops

    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        ib = ib.resize(ia.size)
    ecart = ImageChops.difference(ia, ib).convert("L")
    pixels = list(ecart.getdata())
    part = sum(1 for p in pixels if p > TOLERANCE) / len(pixels)
    moyen = sum(pixels) / len(pixels)

    carte = ecart.point(lambda p: 255 - min(p * 4, 255)).convert("RGB")
    cote = Image.new("RGB", (ia.width * 3 + 24, ia.height), (255, 255, 255))
    cote.paste(ia, (0, 0))
    cote.paste(ib, (ia.width + 12, 0))
    cote.paste(carte, (ia.width * 2 + 24, 0))
    cote.save(SORTIE / f"{nom}-comparaison.png")
    return part, moyen


def main():
    voulus = [a for a in sys.argv[1:] if not a.startswith("-")]
    ecrans = {k: v for k, v in ONGLETS.items() if not voulus or k in voulus}

    if "device" not in sh("devices").replace("List of devices attached", ""):
        print("Aucun appareil branché.")
        return 1
    for paquet in (FLUTTER, DOTNET):
        if paquet not in sh("shell", "pm", "list", "packages", paquet):
            print(f"{paquet} n'est pas installée sur l'appareil.")
            return 1

    captures = {}
    for paquet, marque in ((FLUTTER, "flutter"), (DOTNET, "dotnet")):
        ouvrir(paquet)
        for nom, onglet in ecrans.items():
            if not toucher(onglet, pause=5):
                print(f"  {marque} : onglet « {onglet} » introuvable, écran ignoré")
                continue
            captures.setdefault(nom, {})[marque] = capturer(f"{nom}-{marque}")

    print(f"\n{'écran':12} {'pixels écartés':>16} {'écart moyen':>13}")
    alertes = 0
    for nom in ecrans:
        paire = captures.get(nom, {})
        if len(paire) != 2:
            print(f"{nom:12} {'non comparé':>16}")
            continue
        part, moyen = comparer(paire["flutter"], paire["dotnet"], nom)
        marque = " " if part <= SEUIL_ALERTE else "!"
        print(f"{nom:12} {part * 100:15.2f}% {moyen:12.1f} {marque}")
        alertes += part > SEUIL_ALERTE

    print(f"\nImages dans {SORTIE}")
    return 1 if alertes else 0


if __name__ == "__main__":
    sys.exit(main())
