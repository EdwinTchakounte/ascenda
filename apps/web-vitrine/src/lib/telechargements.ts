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
const FICHIER = "ascenda.apk";

export type Telechargement = { url: string; megaoctets: number } | null;

export function apk(): Telechargement {
  try {
    const chemin = join(process.cwd(), "public", "telechargements", FICHIER);
    const info = statSync(chemin);
    return {
      url: `/telechargements/${FICHIER}`,
      megaoctets: Math.round((info.size / 1024 / 1024) * 10) / 10,
    };
  } catch {
    return null;
  }
}
