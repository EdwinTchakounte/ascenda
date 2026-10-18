#!/usr/bin/env python3
"""Compare au pixel les écrans des deux applications, sur l'appareil branché.

Les deux applications s'installent côte à côte : elles n'ont pas le même
identifiant. Ce banc ouvre le même écran dans chacune, capture, puis mesure
l'écart : part de pixels qui diffèrent, écart moyen, et une carte des
différences qui montre où.

    ./tests/comparer_portage.py                 # tous les écrans appariés
    ./tests/comparer_portage.py jour quiz       # seulement ceux-là

Les images sortent dans docs/comparaison-portage/ : pour chaque écran, la
capture Flutter, la capture .NET, et la carte des différences.
"""
import pathlib
import subprocess
import sys
import time

ADB = str(pathlib.Path.home() / "Android/Sdk/platform-tools/adb")
RACINE = pathlib.Path(__file__).resolve().parent.parent
SORTIE = RACINE / "docs/comparaison-portage"

FLUTTER = "com.ascenda.ascenda"
DOTNET = "com.ascenda.dotnet"

# Chaque écran, et le chemin qui l'ouvre dans chacune des deux applications.
ECRANS = {
    "jour": ("/aujourdhui", "//onglets/jour"),
    "livres": ("/bibliotheque", "//onglets/livres"),
    "agent": ("/agent", "//onglets/agent"),
    "chemin": ("/progression", "//onglets/chemin"),
}

TOLERANCE = 2          # un écart de teinte sous ce seuil ne compte pas
SEUIL_ALERTE = 0.02    # au-delà de 2 % de pixels écartés, on le signale


def sh(*args, binaire=False):
    r = subprocess.run([ADB, *args], capture_output=True)
    return r.stdout if binaire else r.stdout.decode("utf-8", "ignore")


def appareil_present():
    return "device" in sh("devices").replace("List of devices attached", "")


def installee(paquet):
    return paquet in sh("shell", "pm", "list", "packages", paquet)


def capturer(paquet, chemin, nom, suffixe):
    sh("shell", "am", "force-stop", paquet)
    sh("shell", "am", "start", "-n", f"{paquet}/.MainActivity")
    time.sleep(6)
    # La navigation profonde passe par le même intent dans les deux applications.
    sh("shell", "am", "start", "-a", "android.intent.action.VIEW",
       "-d", f"ascenda:{chemin}", paquet)
    time.sleep(4)
    SORTIE.mkdir(parents=True, exist_ok=True)
    f = SORTIE / f"{nom}-{suffixe}.png"
    f.write_bytes(sh("exec-out", "screencap", "-p", binaire=True))
    return f


def comparer(a, b, nom):
    from PIL import Image, ImageChops

    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        ib = ib.resize(ia.size)
    ecart = ImageChops.difference(ia, ib)
    gris = ecart.convert("L")
    pixels = list(gris.getdata())
    differents = sum(1 for p in pixels if p > TOLERANCE)
    part = differents / len(pixels)
    moyen = sum(pixels) / len(pixels)

    carte = Image.new("RGB", ia.size, (255, 255, 255))
    carte.paste(ecart.point(lambda p: 255 - min(p * 4, 255)))
    carte.save(SORTIE / f"{nom}-ecart.png")
    return part, moyen


def main():
    voulus = [a for a in sys.argv[1:] if not a.startswith("-")]
    ecrans = {k: v for k, v in ECRANS.items() if not voulus or k in voulus}

    if not appareil_present():
        print("Aucun appareil branché. Reliez le téléphone et réessayez.")
        return 1
    for paquet in (FLUTTER, DOTNET):
        if not installee(paquet):
            print(f"{paquet} n'est pas installée sur l'appareil.")
            return 1

    print(f"{'écran':14} {'pixels écartés':>16} {'écart moyen':>13}")
    echec = 0
    for nom, (route_flutter, route_dotnet) in ecrans.items():
        a = capturer(FLUTTER, route_flutter, nom, "flutter")
        b = capturer(DOTNET, route_dotnet, nom, "dotnet")
        part, moyen = comparer(a, b, nom)
        marque = " " if part <= SEUIL_ALERTE else "!"
        print(f"{nom:14} {part * 100:15.2f}% {moyen:12.1f} {marque}")
        echec += part > SEUIL_ALERTE

    print(f"\nImages dans {SORTIE}")
    if echec:
        print(f"{echec} écran(s) au-dessus de {SEUIL_ALERTE * 100:.0f} % d'écart.")
    return 1 if echec else 0


if __name__ == "__main__":
    sys.exit(main())
