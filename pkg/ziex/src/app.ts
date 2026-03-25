import { run } from "./runtime";
import type { DurableObjectNamespace } from "./runtime";
import type { KVNamespace } from "./kv";
import type { D1Database } from "./db";
import type { WASI } from "./wasi";

/**
 * Anything that can be resolved to a `WebAssembly.Module`:
 * - `WebAssembly.Module` — already compiled (Cloudflare Workers, wrangler)
 * - `ArrayBuffer` / `ArrayBufferView` — raw WASM bytes
 * - `Response` — a fetch() response whose body is the WASM binary
 * - `string` — an HTTP(S) URL or an absolute file path (Bun)
 * - `URL` — a URL object
 */
export type WasmInput =
    | WebAssembly.Module
    | ArrayBuffer
    | ArrayBufferView
    | Response
    | string
    | URL;

/**
 * Resolve any supported WASM input to a compiled `WebAssembly.Module`.
 * The result is NOT cached here — cache it at the call site if needed.
 */
export async function resolveModule(input: WasmInput): Promise<WebAssembly.Module> {
    if (typeof input === 'string') {
        if (input.startsWith('http://') || input.startsWith('https://')) {
            return (WebAssembly as any).compileStreaming(fetch(input));
        }
        const url = input.startsWith('/') ? `file://${input}` : input;
        return (WebAssembly as any).compile(await fetch(url).then(r => r.arrayBuffer()));
    }

    if (input instanceof URL) {
        return (WebAssembly as any).compileStreaming(fetch(input));
    }

    if (input instanceof Response) {
        return (WebAssembly as any).compileStreaming(input);
    }

    if (input instanceof ArrayBuffer) {
        return (WebAssembly as any).compile(input);
    }
    if (ArrayBuffer.isView(input)) {
        return (WebAssembly as any).compile((input as ArrayBufferView).buffer);
    }

    // Anything else is assumed to be an already-compiled WebAssembly.Module.
    // Intentionally avoid `instanceof WebAssembly.Module` — it fails across
    // different VM contexts (e.g. Vercel's edge runtime simulator).
    return input as unknown as WebAssembly.Module;
}

/** Keys of `Env` whose value extends {@link KVNamespace}. */
type KVKey<Env> = { [K in keyof Env]: Env[K] extends KVNamespace ? K : never }[keyof Env];

/** Keys of `Env` whose value extends {@link DurableObjectNamespace}. */
type DOKey<Env> = { [K in keyof Env]: Env[K] extends DurableObjectNamespace ? K : never }[keyof Env];
type DBKey<Env> = { [K in keyof Env]: Env[K] extends D1Database ? K : never }[keyof Env];

type ZiexOptions<Env> = {
    /** WASM module — accepts any {@link WasmInput}. Resolved and cached on first request. */
    module: WasmInput;
    /** Optional pre-configured WASI instance. */
    wasi?: WASI;
    /** Extra WASM import namespaces. */
    imports?: (mem: () => WebAssembly.Memory) => Record<string, Record<string, unknown>>;
    /**
     * KV namespace bindings. Two forms are supported:
     *
     * - **Env key**: a single key from `Env` whose value is a `KVNamespace` — used as the `"default"` binding.
     * - **Name map**: `{ [bindingName]: envKey }` — map namespace names to env keys.
     *
     * @example Single env key (becomes the "default" binding)
     * ```ts
     * kv: "MY_KV"
     * ```
     * @example Name map
     * ```ts
     * kv: { default: "MY_KV", users: "USERS_KV" }
     * ```
     */
    kv?: KVKey<Env> | Record<string, KVKey<Env>>;
    /**
     * D1 database bindings. Same shape as `kv`:
     *
     * - `"DB"` maps `env.DB` to the `"default"` database binding.
     * - `{ default: "DB", analytics: "ANALYTICS_DB" }` maps multiple bindings.
     */
    db?: DBKey<Env> | Record<string, DBKey<Env>>;
    /**
     * Env key whose value is a `DurableObjectNamespace` for WebSocket pub/sub.
     * Requires `createWebSocketDO` export on the worker.
     *
     * @example
     * ```ts
     * websocket: "ChatRoom"
     * ```
     */
    websocket?: DOKey<Env>;
};

/**
 * Main Ziex application class. Mirrors the Hono API style — construct once,
 * export as default, and the runtime calls `fetch` for you.
 *
 * Works on Cloudflare Workers, Bun, and Vercel Edge out of the box.
 *
 * @example Cloudflare Workers / wrangler
 * ```ts
 * import { Ziex } from "ziex";
 * import module from "./app.wasm";
 *
 * const app = new Ziex<Env>({
 *   module,
 *   kv: (env) => ({ default: env.KV }),
 * });
 * export default app;
 * ```
 *
 * @example Bun
 * ```ts
 * import { Ziex } from "ziex";
 * import wasmPath from "./app.wasm" with { type: "wasm" };
 *
 * const app = new Ziex({ module: wasmPath });
 * export default app;
 * ```
 *
 * @example Vercel Edge
 * ```ts
 * import { Ziex } from "ziex";
 * import { handle } from "ziex/vercel";
 *
 * const app = new Ziex({ module: "https://example.com/app.wasm" });
 * export default handle(app);
 * ```
 */
export class Ziex<Env = Record<string, unknown>> {
    private readonly options: ZiexOptions<Env>;
    private resolved: WebAssembly.Module | null = null;

    constructor(options: ZiexOptions<Env>) {
        this.options = options;
    }

    private async getModule(): Promise<WebAssembly.Module> {
        if (!this.resolved) this.resolved = await resolveModule(this.options.module);
        return this.resolved;
    }

    private resolveKV(env: Env): Record<string, KVNamespace> | undefined {
        const { kv } = this.options;
        if (kv === undefined) return undefined;
        if (typeof kv === 'object' && kv !== null) {
            // { [name]: envKey } — map of namespace names to env keys
            const result: Record<string, KVNamespace> = {};
            for (const [name, key] of Object.entries(kv)) {
                result[name] = env[key as keyof Env] as unknown as KVNamespace;
            }
            return result;
        }
        // Single env key — becomes the "default" binding
        return { default: env[kv as keyof Env] as unknown as KVNamespace };
    }

    private resolveDB(env: Env): Record<string, D1Database> | undefined {
        const { db } = this.options;
        if (db === undefined) return undefined;
        if (typeof db === "object" && db !== null) {
            const result: Record<string, D1Database> = {};
            for (const [name, key] of Object.entries(db)) {
                result[name] = env[key as keyof Env] as unknown as D1Database;
            }
            return result;
        }
        return { default: env[db as keyof Env] as unknown as D1Database };
    }

    /**
     * Fetch handler called by the runtime on every request.
     *
     * Arrow function so `this` is always the class instance, even when the
     * runtime extracts `fetch` from the exported object (e.g. Bun).
     */
    fetch = async (
        request: Request,
        env: Env,
        ctx?: { waitUntil(p: Promise<unknown>): void },
    ): Promise<Response> => {
        const module = await this.getModule();
        const { wasi, imports, websocket } = this.options;
        return run({
            request,
            env,
            ctx,
            module,
            wasi,
            imports,
            kv: this.resolveKV(env),
            db: this.resolveDB(env),
            websocket: websocket !== undefined ? env[websocket as keyof Env] as unknown as DurableObjectNamespace : undefined,
        });
    };
}
