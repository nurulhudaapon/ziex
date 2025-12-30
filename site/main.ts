import React from "react";
import { createRoot } from "react-dom/client";
import { prepareComponent, filterComponents } from "ziex/react";
import { init } from "../packages/ziex/src/wasm";

/** The components array is generated once `zig build` or `zx dev` or `zx serve` is run. **/
import { components } from "@ziex/components";

for (const component of filterComponents(components)) {
  prepareComponent(component).then(({ domNode, Component, props }) =>
    createRoot(domNode).render(React.createElement(Component, props)),
  ).catch(() => 0);
}

init();