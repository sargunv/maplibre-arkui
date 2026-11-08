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
            { label: "Style the map", slug: "styling" },
            { label: "Control the camera", slug: "camera" },
            { label: "Add data to the map", slug: "layers" },
            { label: "Handle gestures and clicks", slug: "interaction" },
            { label: "Query and highlight features", slug: "features" },
            { label: "Overlay ArkUI content", slug: "controls" },
            { label: "Show the user's location", slug: "location" },
            { label: "Capture a map image", slug: "snapshots" },
            { label: "Use maps offline", slug: "offline" },
            { label: "Rewrite or serve map requests", slug: "requests" },
            { label: "Handle errors and logs", slug: "errors" },
            { label: "Use MapLibre Native FFI", slug: "ffi" },
          ],
        },
        {
          label: "Concepts",
          items: [{ label: "Expressions in ArkTS", slug: "expressions" }],
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
