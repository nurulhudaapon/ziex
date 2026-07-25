import { type WasmAllocRef, writeBytesOut, writeJsonOut } from "../../wasm/core";
import type { KVNamespace, SyncKVNamespace } from "../kv";

export type { WasmAllocRef };

function putOptions(ttlSeconds: number): { expirationTtl: number } | undefined {
    if (ttlSeconds < 60) return undefined;
    return { expirationTtl: ttlSeconds };
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
 * Build the `__zx_kv` host functions for key/value namespace bindings.
 *
 * ```ts
 * if (__FEAT_KV__) importObject.__zx_kv = createKVImports(bindings, getMemory, allocRef);
 * ```
 */
export function createKVImports(
    bindings: Record<string, KVNamespace>,
    getMemory: () => WebAssembly.Memory,
    allocRef: WasmAllocRef,
): WebAssembly.ModuleImports {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    function readStr(ptr: number, len: number): string {
        return decoder.decode(new Uint8Array(getMemory().buffer, ptr, len));
    }

    function binding(ns: string): KVNamespace | null {
        return bindings[ns] ?? bindings["default"] ?? null;
    }

    const Suspending = (WebAssembly as any).Suspending;
    if (typeof Suspending !== "function") {
        function syncBinding(ns: string): SyncKVNamespace | null {
            const candidate = binding(ns);
            return candidate && isSyncKVNamespace(candidate) ? candidate : null;
        }

        return {
            kv_get: (ns_ptr: number, ns_len: number, key_ptr: number, key_len: number, out_ptr: number): number => {
                const b = syncBinding(readStr(ns_ptr, ns_len));
                if (!b) return -1;
                const value = b.getSync(readStr(key_ptr, key_len));
                if (value === null) return -1;
                return writeBytesOut(getMemory, allocRef, out_ptr, encoder.encode(value));
            },
            kv_put: (ns_ptr: number, ns_len: number, key_ptr: number, key_len: number, val_ptr: number, val_len: number, ttl_seconds: number): number => {
                const b = syncBinding(readStr(ns_ptr, ns_len));
                if (!b) return 0;
                b.putSync(readStr(key_ptr, key_len), readStr(val_ptr, val_len), putOptions(ttl_seconds));
                return 0;
            },
            kv_delete: (ns_ptr: number, ns_len: number, key_ptr: number, key_len: number): number => {
                const b = syncBinding(readStr(ns_ptr, ns_len));
                if (!b) return 0;
                b.deleteSync(readStr(key_ptr, key_len));
                return 0;
            },
            kv_list: (ns_ptr: number, ns_len: number, pfx_ptr: number, pfx_len: number, out_ptr: number): number => {
                const b = syncBinding(readStr(ns_ptr, ns_len));
                if (!b) return writeJsonOut(getMemory, allocRef, out_ptr, []);
                const prefix = readStr(pfx_ptr, pfx_len);
                const result = b.listSync(prefix.length > 0 ? { prefix } : undefined);
                return writeJsonOut(getMemory, allocRef, out_ptr, result.keys.map((k) => k.name));
            },
        };
    }

    return {
        kv_get: new Suspending(async (
            ns_ptr: number, ns_len: number,
            key_ptr: number, key_len: number,
            out_ptr: number,
        ): Promise<number> => {
            const b = binding(readStr(ns_ptr, ns_len));
            if (!b) return -1;
            const value = await b.get(readStr(key_ptr, key_len));
            if (value === null) return -1;
            return writeBytesOut(getMemory, allocRef, out_ptr, encoder.encode(value));
        }),

        kv_put: new Suspending(async (
            ns_ptr: number, ns_len: number,
            key_ptr: number, key_len: number,
            val_ptr: number, val_len: number,
            ttl_seconds: number,
        ): Promise<number> => {
            const b = binding(readStr(ns_ptr, ns_len));
            if (!b) return -1;
            await b.put(readStr(key_ptr, key_len), readStr(val_ptr, val_len), putOptions(ttl_seconds));
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
            out_ptr: number,
        ): Promise<number> => {
            const b = binding(readStr(ns_ptr, ns_len));
            if (!b) return writeJsonOut(getMemory, allocRef, out_ptr, []);
            const prefix = readStr(prefix_ptr, prefix_len);
            const result = await b.list(prefix.length > 0 ? { prefix } : undefined);
            const names = result.keys.map((k) => k.name);
            if (names.length === 0) {
                new DataView(getMemory().buffer).setUint32(out_ptr, 0, true);
                return 0;
            }
            return writeJsonOut(getMemory, allocRef, out_ptr, names);
        }),
    };
}
