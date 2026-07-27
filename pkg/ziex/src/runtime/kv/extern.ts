import {
    type WasmAllocRef,
    textDecoder,
    textEncoder,
    writeBytesOut,
    writeJsonOut,
} from "../../wasm/core";
import type { KVNamespace, SyncKVNamespace } from "../kv";

export type { WasmAllocRef };

const Suspending = (WebAssembly as any).Suspending as
    | (new <T extends (...args: any[]) => any>(fn: T) => T)
    | undefined;
const jspi = typeof Suspending === "function";
const miss = jspi ? -1 : 0;

function putOptions(ttlSeconds: number): { expirationTtl: number } | undefined {
    if (ttlSeconds < 60) return undefined;
    return { expirationTtl: ttlSeconds };
}

/** Our backends export `del`; Cloudflare KV uses `delete`. */
function kvDel(binding: KVNamespace, key: string): ReturnType<KVNamespace["del"]> {
    const b = binding as KVNamespace & { delete?: KVNamespace["del"] };
    return (b.del ?? b.delete)!.call(b, key);
}

function isSyncKVNamespace(binding: KVNamespace): binding is SyncKVNamespace {
    return typeof binding.get === "function" && binding.get.constructor.name !== "AsyncFunction";
}

function listOpts(prefix: string): { prefix: string } | undefined {
    return prefix.length > 0 ? { prefix } : undefined;
}

function maybeThen<T, R>(r: T | Promise<T>, f: (v: T) => R): R | Promise<R> {
    return r instanceof Promise ? r.then(f) : f(r);
}

function readStr(getMemory: () => WebAssembly.Memory, ptr: number, len: number): string {
    return textDecoder.decode(new Uint8Array(getMemory().buffer, ptr, len));
}

function resolve(
    bindings: Record<string, KVNamespace>,
    ns: string,
): KVNamespace | null {
    const b = bindings[ns] ?? bindings["default"] ?? null;
    if (!b || jspi) return b;
    return isSyncKVNamespace(b) ? b : null;
}

function encodeGet(
    getMemory: () => WebAssembly.Memory,
    allocRef: WasmAllocRef,
    value: string | null,
    out_ptr: number,
): number {
    if (value === null) return -1;
    return writeBytesOut(getMemory, allocRef, out_ptr, textEncoder.encode(value));
}

function encodeList(
    getMemory: () => WebAssembly.Memory,
    allocRef: WasmAllocRef,
    names: string[],
    out_ptr: number,
): number {
    if (names.length === 0) {
        new DataView(getMemory().buffer).setUint32(out_ptr, 0, true);
        return 0;
    }
    return writeJsonOut(getMemory, allocRef, out_ptr, names);
}

function get(
    b: KVNamespace,
    key: string,
    out_ptr: number,
    getMemory: () => WebAssembly.Memory,
    allocRef: WasmAllocRef,
): number | Promise<number> {
    return maybeThen(b.get(key), (v) => encodeGet(getMemory, allocRef, v, out_ptr));
}

function put(b: KVNamespace, key: string, val: string, ttl: number): number | Promise<number> {
    return maybeThen(b.put(key, val, putOptions(ttl)), () => 0);
}

function del(b: KVNamespace, key: string): number | Promise<number> {
    return maybeThen(kvDel(b, key), () => 0);
}

function list(
    b: KVNamespace,
    prefix: string,
    out_ptr: number,
    getMemory: () => WebAssembly.Memory,
    allocRef: WasmAllocRef,
): number | Promise<number> {
    return maybeThen(b.list(listOpts(prefix)), (result) =>
        encodeList(getMemory, allocRef, result.keys.map((k) => k.name), out_ptr),
    );
}

function wrapImport<T extends (...args: number[]) => number | Promise<number>>(impl: T): T {
    if (!jspi) {
        return ((...args: Parameters<T>) => {
            const r = impl(...args);
            if (r instanceof Promise) throw new Error("async kv binding requires JSPI");
            return r;
        }) as T;
    }
    return new Suspending!(impl);
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
    return {
        kv_get: wrapImport((ns_ptr, ns_len, key_ptr, key_len, out_ptr) => {
            const b = resolve(bindings, readStr(getMemory, ns_ptr, ns_len));
            if (!b) return -1;
            return get(b, readStr(getMemory, key_ptr, key_len), out_ptr, getMemory, allocRef);
        }),

        kv_put: wrapImport((ns_ptr, ns_len, key_ptr, key_len, val_ptr, val_len, ttl_seconds) => {
            const b = resolve(bindings, readStr(getMemory, ns_ptr, ns_len));
            if (!b) return miss;
            return put(
                b,
                readStr(getMemory, key_ptr, key_len),
                readStr(getMemory, val_ptr, val_len),
                ttl_seconds,
            );
        }),

        kv_delete: wrapImport((ns_ptr, ns_len, key_ptr, key_len) => {
            const b = resolve(bindings, readStr(getMemory, ns_ptr, ns_len));
            if (!b) return miss;
            return del(b, readStr(getMemory, key_ptr, key_len));
        }),

        kv_list: wrapImport((ns_ptr, ns_len, pfx_ptr, pfx_len, out_ptr) => {
            const b = resolve(bindings, readStr(getMemory, ns_ptr, ns_len));
            if (!b) return writeJsonOut(getMemory, allocRef, out_ptr, []);
            return list(b, readStr(getMemory, pfx_ptr, pfx_len), out_ptr, getMemory, allocRef);
        }),
    };
}
