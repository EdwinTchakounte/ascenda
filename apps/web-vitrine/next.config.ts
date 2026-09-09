import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Sortie autonome : l'image de production n'embarque que ce qui sert.
  output: "standalone",
  /* config options here */
};

export default nextConfig;
