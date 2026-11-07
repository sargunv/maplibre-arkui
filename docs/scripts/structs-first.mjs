// A TypeDoc plugin that lists the struct components first in each category of
// the API reference, before the classes, interfaces, and functions they take,
// keeping TypeDoc's order otherwise. emit-declarations.mjs marks each struct
// with its `@ComponentV2` decorator, as the modifier tag `@arkuiComponentV2`.
import { Converter } from "typedoc";

/** @param {import("typedoc").Application} app */
export function load(app) {
  // After TypeDoc's own categorizing and sorting, which runs at -200.
  app.converter.on(
    Converter.EVENT_RESOLVE_END,
    (context) => {
      for (const category of context.project.categories ?? []) {
        // A stable sort, so each part keeps TypeDoc's order.
        category.children.sort((a, b) => isStruct(b) - isStruct(a));
      }
    },
    -300,
  );
}

function isStruct(reflection) {
  return reflection.comment?.hasModifier("@arkuiComponentV2") ? 1 : 0;
}
