// @ts-ignore
import module from "../zig-out/bin/ziex_dev.wasm";
import { worker } from "../../pkg/ziex/src/cloudflare";
import { WASI } from "@cloudflare/workers-wasi";

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext) {
    return worker.run({
      request,
      env,
      ctx,
      module,
      kv: { default: env.KV },
      wasi: new WASI(),
    });
  },
} satisfies ExportedHandler<Env>;
