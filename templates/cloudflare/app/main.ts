import { Ziex } from "ziex";
import module from "../zig-out/bin/zx_app.wasm";

export default new Ziex<Env>({ module, kv: "KV" });
