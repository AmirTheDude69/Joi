import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Joi — Daily AI Companion",
    short_name: "Joi",
    description:
      "A warm productivity companion with transparent tools, editable memory, and approval-first actions.",
    start_url: "/",
    display: "standalone",
    background_color: "#fff8f1",
    theme_color: "#b84f2d",
    orientation: "portrait-primary",
    icons: [
      {
        src: "/joi/icon.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "any",
      },
      {
        src: "/joi/icon.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "maskable",
      },
    ],
  };
}
