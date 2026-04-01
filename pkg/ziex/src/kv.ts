// Minimal type definition for a key-value namespace
export interface KVNamespace {
    get(key: string): Promise<string | null>;
    put(key: string, value: string, options?: { expiration?: number; expirationTtl?: number }): Promise<void>;
    delete(key: string): Promise<void>;
    list(options?: { prefix?: string }): Promise<{ keys: { name: string }[] }>;
}

export interface SyncKVNamespace extends KVNamespace {
    getSync(key: string): string | null;
    putSync(key: string, value: string, options?: { expiration?: number; expirationTtl?: number }): void;
    deleteSync(key: string): void;
    listSync(options?: { prefix?: string }): { keys: { name: string }[] };
}

/**
 * In-memory KV namespace. Used as the default shim on platforms that don't
 * provide a real KV binding (e.g. Vercel). Data lives only for the lifetime
 * of the isolate instance.
 */
export function createMemoryKV(): KVNamespace {
    const store = new Map<string, string>();
    return {
        async get(key) { return store.get(key) ?? null; },
        async put(key, value) { store.set(key, value); },
        async delete(key) { store.delete(key); },
        async list(options) {
            const keys = [...store.keys()]
                .filter(k => !options?.prefix || k.startsWith(options.prefix))
                .map(name => ({ name }));
            return { keys };
        },
    };
}

function isSyncKVNamespace(binding: KVNamespace): binding is SyncKVNamespace {
    const candidate = binding as Partial<SyncKVNamespace>;
    return (
        typeof candidate.getSync === "function" &&
        typeof candidate.putSync === "function" &&
        typeof candidate.deleteSync === "function" &&
        typeof candidate.listSync === "function"
    );
}

/**
 * Create a `__zx_kv` import object for use with `run({ kv: ... })`.
 * Always returns a valid import object. When JSPI is unavailable it uses
 * synchronous bindings when available, otherwise falls back to stubbed no-ops.
 */
export function createKVImports(
    bindings: Record<string, KVNamespace>,
    getMemory: () => WebAssembly.Memory,
): Record<string, unknown> {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    function readStr(ptr: number, len: number): string {
        return decoder.decode(new Uint8Array(getMemory().buffer, ptr, len));
    }

    function writeBytes(buf_ptr: number, buf_max: number, data: Uint8Array): number {
        if (data.length > buf_max) return -2;
        new Uint8Array(getMemory().buffer, buf_ptr, data.length).set(data);
        return data.length;
    }

    function binding(ns: string): KVNamespace | null {
        return bindings[ns] ?? bindings["default"] ?? null;
    }

    const Suspending = (WebAssembly as any).Suspending;
    if (typeof Suspending !== 'function') {
        function syncBinding(ns: string): SyncKVNamespace | null {
            const candidate = binding(ns);
            return candidate && isSyncKVNamespace(candidate) ? candidate : null;
        }

        return {
            kv_get: (ns_ptr: number, ns_len: number, key_ptr: number, key_len: number, buf_ptr: number, buf_max: number): number => {
                const b = syncBinding(readStr(ns_ptr, ns_len));
                if (!b) return -1;
                const value = b.getSync(readStr(key_ptr, key_len));
                if (value === null) return -1;
                return writeBytes(buf_ptr, buf_max, encoder.encode(value));
            },
            kv_put: (ns_ptr: number, ns_len: number, key_ptr: number, key_len: number, val_ptr: number, val_len: number): number => {
                const b = syncBinding(readStr(ns_ptr, ns_len));
                if (!b) return 0;
                b.putSync(readStr(key_ptr, key_len), readStr(val_ptr, val_len));
                return 0;
            },
            kv_delete: (ns_ptr: number, ns_len: number, key_ptr: number, key_len: number): number => {
                const b = syncBinding(readStr(ns_ptr, ns_len));
                if (!b) return 0;
                b.deleteSync(readStr(key_ptr, key_len));
                return 0;
            },
            kv_list: (ns_ptr: number, ns_len: number, pfx_ptr: number, pfx_len: number, buf_ptr: number, buf_max: number): number => {
                const b = syncBinding(readStr(ns_ptr, ns_len));
                if (!b) return writeBytes(buf_ptr, buf_max, encoder.encode("[]"));
                const prefix = readStr(pfx_ptr, pfx_len);
                const result = b.listSync(prefix.length > 0 ? { prefix } : undefined);
                return writeBytes(buf_ptr, buf_max, encoder.encode(JSON.stringify(result.keys.map((k) => k.name))));
            },
        };
    }

    return {
        kv_get: new Suspending(async (
            ns_ptr: number, ns_len: number,
            key_ptr: number, key_len: number,
            buf_ptr: number, buf_max: number,
        ): Promise<number> => {
            const b = binding(readStr(ns_ptr, ns_len));
            if (!b) return -1;
            const value = await b.get(readStr(key_ptr, key_len));
            if (value === null) return -1;
            return writeBytes(buf_ptr, buf_max, encoder.encode(value));
        }),

        kv_put: new Suspending(async (
            ns_ptr: number, ns_len: number,
            key_ptr: number, key_len: number,
            val_ptr: number, val_len: number,
        ): Promise<number> => {
            const b = binding(readStr(ns_ptr, ns_len));
            if (!b) return -1;
            await b.put(readStr(key_ptr, key_len), readStr(val_ptr, val_len));
            return 0;
        }),

        kv_delete: new Suspending(async (
            ns_ptr: number, ns_len: number,
            key_ptr: number, key_len: number,
        ): Promise<number> => {
            const b = binding(readStr(ns_ptr, ns_len));
            if (!b) return -1;
            await b.delete(readStr(key_ptr, key_len));
            return 0;
        }),

        kv_list: new Suspending(async (
            ns_ptr: number, ns_len: number,
            prefix_ptr: number, prefix_len: number,
            buf_ptr: number, buf_max: number,
        ): Promise<number> => {
            const b = binding(readStr(ns_ptr, ns_len));
            if (!b) return writeBytes(buf_ptr, buf_max, encoder.encode("[]"));
            const prefix = readStr(prefix_ptr, prefix_len);
            const result = await b.list(prefix.length > 0 ? { prefix } : undefined);
            return writeBytes(buf_ptr, buf_max, encoder.encode(JSON.stringify(result.keys.map((k) => k.name))));
        }),
    };
}
