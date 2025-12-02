import React from "react";
import { createRoot } from "react-dom/client";

import { filterComponents, prepareComponent } from "ziex/react";
import { init } from "ziex/wasm";

import { components } from "@ziex/components"; // The components array is generated once `zig build` or `zx dev` or `zx serve` is run.

/** Initialize the ZX WASM instance */
init();

/** Render the React components */
for (const component of filterComponents(components)) {
  prepareComponent(component).then(({ domNode, Component, props }) =>
    createRoot(domNode).render(React.createElement(Component, props)),
  );
}
