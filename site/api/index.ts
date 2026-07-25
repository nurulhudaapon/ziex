import module from "../zig-out/bin/ziex_dev.wasm?module";
import { Ziex } from "../zig-out/pkg/ziex";
import { handle } from "../zig-out/pkg/ziex/platforms/vercel";

export const config = { runtime: "edge" };

export default handle(new Ziex({ module }));
