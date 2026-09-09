import Image from "next/image";

/**
 * La marque ASCENDA : le « A » doré du logo, avec sa comète, son étoile et la
 * silhouette aux bras levés. Servie comme image plutôt que redessinée : un
 * logo approximatif abîme une identité, et celui-ci porte des dégradés qu'un
 * tracé vectoriel simple ne rendrait pas.
 */
export default function Logo({
  taille = 32,
  className = "",
}: {
  taille?: number;
  className?: string;
}) {
  return (
    <Image
      src="/images/marque-192.png"
      alt=""
      width={taille}
      height={taille}
      className={className}
      priority
    />
  );
}
