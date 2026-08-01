import { Ziex, type StickyKey } from "../../app";
import { get, put, del, list } from "../../runtime/kv/memory";
import { createStatefulFetch } from "./stateful";

export { Ziex, resolveModule } from "../../app";
export type { WasmInput, ZiexOptions, StickyKey } from "../../app";

export type StatefulOptions<Env> = {
    /** Env binding for sticky long-lived fetch (must match wrangler `durable_objects.bindings`). */
    binding: StickyKey<Env>;
};

/**
 * Sticky long-lived fetch class for Cloudflare (WebSocket upgrades + pub/sub).
 *
 * Reuses the app's module/kv/db/imports and registers the env binding for upgrade forwarding.
 *
 * @example
 * ```ts
 * import { Ziex } from "ziex";
 * import { stateful } from "ziex/cloudflare";
 *
 * const app = new Ziex<Env>({ module, kv: "KV", db: "DB" });
 * export const ChatRoom = stateful(app, { binding: "CHAT_ROOM" });
 * export default app;
 * ```
 */
export function stateful<Env>(app: Ziex<Env>, options: StatefulOptions<Env>) {
    const host = app.stickyHost(options.binding);
    return createStatefulFetch(host.module, {
        kv: (env) => host.kv(env as Env) ?? { default: { get, put, del, list } },
        db: (env) => host.db(env as Env) ?? {},
        imports: host.imports,
    });
}
