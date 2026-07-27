export type { WasmAllocRef } from "../wasm/core";

/** Key/value namespace binding. Cloudflare KV–shaped so CF bindings work as-is; other backends adapt to the same interface. */
export interface KVNamespace {
    get(key: string): Promise<string | null>;
    put(key: string, value: string, options?: { expiration?: number; expirationTtl?: number }): Promise<void>;
    delete(key: string): Promise<void>;
    list(options?: { prefix?: string }): Promise<{ keys: { name: string }[] }>;
}

/** Synchronous KV used when JSPI is unavailable (e.g. localStorage). */
export interface SyncKVNamespace extends KVNamespace {
    getSync(key: string): string | null;
    putSync(key: string, value: string, options?: { expiration?: number; expirationTtl?: number }): void;
    deleteSync(key: string): void;
    listSync(options?: { prefix?: string }): { keys: { name: string }[] };
}

export { createMemoryKV } from "./kv/memory";
export { createLocalStorageKV, type LocalStorageKVOptions } from "./kv/localstorage";
export { createIndexedDbKV, type IndexedDbKVOptions } from "./kv/indexdb";
export { createKVImports } from "./kv/extern";

import { createIndexedDbKV, type IndexedDbKVOptions } from "./kv/indexdb";
import { createLocalStorageKV } from "./kv/localstorage";

export type BrowserKVOptions = IndexedDbKVOptions & {
    storagePrefix?: string;
    forceLocalStorage?: boolean;
};

export function hasJSPI(): boolean {
    return (
        typeof (WebAssembly as any).Suspending === "function" &&
        typeof (WebAssembly as any).promising === "function"
    );
}

/** Prefer IndexedDB when JSPI is available, otherwise localStorage. */
export function createBrowserKVBindings(options: BrowserKVOptions = {}): Record<string, KVNamespace> {
    const namespace = options.namespace ?? "default";
    const isIndexedDb = hasJSPI() && !options.forceLocalStorage;
    return {
        [namespace]: isIndexedDb ? createIndexedDbKV(options) : createLocalStorageKV(options),
    };
}
