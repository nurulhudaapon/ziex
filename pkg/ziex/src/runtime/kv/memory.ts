import type { KVNamespace } from "../kv";

/** `[value, expiresAtMs]` - tuple so slot names can minify. */
type MemoryEntry = [string, number | undefined];

/**
 * In-memory KV. Used as the default shim on platforms that don't provide a
 * real KV binding (e.g. Vercel). Data lives only for the lifetime of the isolate.
 */
export function createMemoryKV(): KVNamespace {
    const store = new Map<string, MemoryEntry>();

    function read(key: string): string | null {
        const entry = store.get(key);
        if (!entry) return null;
        const expiresAt = entry[1];
        if (expiresAt !== undefined && Date.now() >= expiresAt) {
            store.delete(key);
            return null;
        }
        return entry[0];
    }

    function write(key: string, value: string, options?: { expiration?: number; expirationTtl?: number }): void {
        let expiresAt: number | undefined;
        if (options?.expiration !== undefined) {
            expiresAt = options.expiration * 1000;
        } else if (options?.expirationTtl !== undefined) {
            expiresAt = Date.now() + options.expirationTtl * 1000;
        }
        store.set(key, [value, expiresAt]);
    }

    return {
        async get(key) { return read(key); },
        async put(key, value, options) { write(key, value, options); },
        async delete(key) { store.delete(key); },
        async list(options) {
            const keys = [...store.keys()]
                .filter((k) => {
                    if (options?.prefix && !k.startsWith(options.prefix)) return false;
                    return read(k) !== null;
                })
                .map((name) => ({ name }));
            return { keys };
        },
    };
}
