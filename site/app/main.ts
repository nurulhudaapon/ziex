import { Ziex } from "../../pkg/ziex";
import module from "../zig-out/bin/ziex_dev.wasm";

export default new Ziex<Env>({ module, kv: "KV" });
