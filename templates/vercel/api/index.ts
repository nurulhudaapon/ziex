import module from "../zig-out/bin/ziex_app.wasm?module";
import { Ziex } from "../zig-out/pkg/ziex/index.js";
import { handle } from "../zig-out/pkg/ziex/platforms/vercel/index.js";

export const config = { runtime: "edge" };

export default handle(new Ziex({ module }));
