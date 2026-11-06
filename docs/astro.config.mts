import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";
import starlightLinksValidator from "starlight-links-validator";

import { publicDirectoryIndex } from "./src/integrations/public-directory-index";

// GitHub Pages serves the site under the repository's name, at whatever origin
// the Pages settings give it. CI's deploy passes that origin from
// actions/configure-pages, so the site follows a custom domain or a move to
// another owner without a change here.
const site = process.env.DOCS_SITE || "http://localhost:4321";
const base = "/maplibre-arkui";
const repository = "https://github.com/sargunv/maplibre-arkui";

export default defineConfig({
  site,
  base,
  vite: {
    // The pages import their examples from the demo, outside this package.
    server: { fs: { allow: [".."] } },
  },
  integrations: [
    publicDirectoryIndex(base),
    starlight({
      title: "MapLibre ArkUI",
      description:
        "ArkUI components for MapLibre Native maps on HarmonyOS and OpenHarmony.",
      logo: {
        light: "./src/assets/maplibre-logo-square-for-light-bg.svg",
        dark: "./src/assets/maplibre-logo-square-for-dark-bg.svg",
      },
      favicon: "/favicon.svg",
      editLink: { baseUrl: `${repository}/edit/main/docs/` },
      customCss: ["./src/styles/custom.css"],
      plugins: [
        // TypeDoc writes the reference outside Astro's page tree.
        starlightLinksValidator({
          exclude: [`${base}/api/`, `${base}/api/**`],
        }),
      ],
      social: [{ icon: "github", label: "GitHub", href: repository }],
      sidebar: [
        { label: "Overview", link: "/" },
        {
          label: "Guides",
          items: [
            { label: "Getting started", slug: "getting-started" },
            { label: "The map", slug: "map" },
            { label: "The camera", slug: "camera" },
            { label: "Gestures", slug: "gestures" },
            { label: "Ornaments and markers", slug: "ornaments" },
            { label: "Map content", slug: "content" },
            { label: "The style API", slug: "style" },
            { label: "The user's location", slug: "location" },
            { label: "Snapshots", slug: "snapshots" },
            { label: "Requests, offline regions, and logs", slug: "requests" },
          ],
        },
        {
          label: "Concepts",
          items: [
            { label: "Expressions", slug: "expressions" },
            { label: "Errors", slug: "errors" },
          ],
        },
        {
          label: "API reference",
          link: "/api/",
          attrs: { target: "_blank", rel: "noopener noreferrer" },
        },
        {
          label: "Development",
          items: [
            { label: "Build from source", slug: "development" },
            { label: "API guidelines", slug: "api-guidelines" },
          ],
        },
      ],
    }),
  ],
});
