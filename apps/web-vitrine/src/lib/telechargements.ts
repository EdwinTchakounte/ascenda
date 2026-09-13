import { statSync } from "node:fs";
import { join } from "node:path";

/**
 * L'APK, si quelqu'un l'a déposée.
 *
 * Plutôt qu'une variable d'environnement de plus, on regarde si le fichier est
 * là. Publier une version se réduit alors à déposer l'APK dans
 * `public/telechargements/`, et la page l'annonce d'elle-même avec son poids.
 * Rien à reconfigurer, rien à oublier de reconfigurer.
 *
 * Le fichier n'est pas versionné : vingt mégaoctets de binaire n'ont rien à
 * faire dans un dépôt de code.
 */
export type Telechargement = { url: string; megaoctets: number } | null;

function fichier(nom: string): Telechargement {
  try {
    const info = statSync(join(process.cwd(), "public", "telechargements", nom));
    return {
      url: `/telechargements/${nom}`,
      megaoctets: Math.round((info.size / 1024 / 1024) * 10) / 10,
    };
  } catch {
    return null;
  }
}

/** L'APK des téléphones actuels (arm64), vingt mégaoctets. */
export const apk = () => fichier("ascenda.apk");

/**
 * L'APK des téléphones anciens ou d'entrée de gamme dont le système est en 32
 * bits : l'APK arm64 ne s'y installe pas. Une APK universelle couvrirait les
 * deux, mais elle pèse cinquante-cinq mégaoctets, c'est à dire une heure de
 * téléchargement sur les connexions de beaucoup de nos lecteurs.
 */
export const apk32 = () => fichier("ascenda-32bits.apk");
