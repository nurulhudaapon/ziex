import { ZigJS } from "../../../../vendor/jsz/js/src";

/**
 * Core WASM bridge - environment-agnostic (browser + edge).
 * Contains no references to browser globals (document, window, WebSocket, HTMLFormElement).
 */
export const CallbackType = {
    Event: 0,
    FetchSuccess: 1,
    FetchError: 2,
    Timeout: 3,
    Interval: 4,
    WebSocketOpen: 5,
    WebSocketMessage: 6,
    WebSocketError: 7,
    WebSocketClose: 8,
} as const;

export type CallbackTypeValue = typeof CallbackType[keyof typeof CallbackType];
export type CallbackHandler = (callbackType: number, id: bigint, dataRef: bigint) => void;
export type FetchCompleteHandler = (fetchId: bigint, statusCode: number, bodyPtr: number, bodyLen: number, isError: number) => void;

// WebSocket callback handler types (used by both core and browser subclass)
export type WsOnOpenHandler = (wsId: bigint, protocolPtr: number, protocolLen: number) => void;
export type WsOnMessageHandler = (wsId: bigint, dataPtr: number, dataLen: number, isBinary: number) => void;
export type WsOnErrorHandler = (wsId: bigint, msgPtr: number, msgLen: number) => void;
export type WsOnCloseHandler = (wsId: bigint, code: number, reasonPtr: number, reasonLen: number, wasClean: number) => void;

export const jsz = new ZigJS();

// Temporary buffer for reading back references from storeValue
const tempRefBuffer = new ArrayBuffer(8);
const tempRefView = new DataView(tempRefBuffer);

/** Store a value using jsz.storeValue and get the 64-bit reference. */
export function storeValueGetRef(val: any): bigint {
    const originalMemory = jsz.memory;
    jsz.memory = { buffer: tempRefBuffer } as WebAssembly.Memory;
    jsz.storeValue(0, val);
    jsz.memory = originalMemory;
    return tempRefView.getBigUint64(0, true);
}

/** Shared encoder/decoder - avoids allocating new instances on every call. */
export const textDecoder = new TextDecoder();
export const textEncoder = new TextEncoder();

/** Cached Uint8Array view of WASM memory. Invalidated when the buffer grows. */
let memoryView: Uint8Array | null = null;
let memoryBuffer: ArrayBufferLike | null = null;

export function getMemoryView(): Uint8Array {
    const buf = jsz.memory!.buffer;
    if (buf !== memoryBuffer) {
        memoryBuffer = buf;
        memoryView = new Uint8Array(buf);
    }
    return memoryView!;
}

/**
 * Cache for WASM string reads keyed by (ptr, len).
 * Attribute names / tag names are Zig string literals whose pointers are
 * stable for the lifetime of the module, so caching avoids repeated
 * TextDecoder.decode calls for the same pointer+length pair.
 */
const stringCache = new Map<number, string>();
function stringCacheKey(ptr: number, len: number): number { return ptr * 0x10000 + len; }

/** Read a string from WASM memory */
export function readString(ptr: number, len: number): string {
    const key = stringCacheKey(ptr, len);
    const cached = stringCache.get(key);
    if (cached !== undefined) return cached;
    const str = textDecoder.decode(getMemoryView().subarray(ptr, ptr + len));
    stringCache.set(key, str);
    return str;
}

/** Write bytes to WASM memory at a specific location */
export function writeBytes(ptr: number, data: Uint8Array): void {
    getMemoryView().set(data, ptr);
}

export function wrapPromisingExport<F extends (...args: any[]) => any>(fn: F | undefined): F | undefined {
    if (!fn) return undefined;
    const promising = (WebAssembly as any).promising;
    if (typeof promising !== "function") return fn;
    return promising(fn) as F;
}

export function invokeWasmExport<F extends (...args: any[]) => any>(
    fn: F | undefined,
    ...args: Parameters<F>
): void {
    if (!fn) return;
    const result = fn(...args);
    if (result && typeof (result as PromiseLike<unknown>).then === "function") {
        void (result as PromiseLike<unknown>).then(undefined, (error) => {
            console.error(error);
        });
    }
}

/**
 * Core ZX Bridge - works in both browser and edge runtimes.
 * Contains fetch, timers, and logging. No DOM or browser-WebSocket references.
 *
 * Extend this class in browser environments to add DOM and WebSocket support.
 */
export class ZxBridgeCore {
    #intervals: Map<bigint, number> = new Map();

    protected readonly _alloc: (size: number) => number;
    readonly #handler: CallbackHandler | undefined;
    readonly #fetchCompleteHandler: FetchCompleteHandler;

    constructor(exports: WebAssembly.Exports) {
        this._alloc = exports.__zx_alloc as (size: number) => number;
        this.#handler = wrapPromisingExport(exports.__zx_cb as CallbackHandler | undefined);
        const fetchCompleteHandler = wrapPromisingExport(exports.__zx_fetch_complete as FetchCompleteHandler | undefined);
        if (!fetchCompleteHandler) {
            throw new Error("__zx_fetch_complete not exported from WASM");
        }
        this.#fetchCompleteHandler = fetchCompleteHandler;
        if (exports.memory) jsz.memory = exports.memory as WebAssembly.Memory;
    }

    /** Invoke the unified callback handler */
    #invoke(type: CallbackTypeValue, id: bigint, data: any): void {
        const handler = this.#handler;
        if (!handler) {
            console.warn('__zx_cb not exported from WASM');
            return;
        }
        const dataRef = storeValueGetRef(data);
        invokeWasmExport(handler, type, id, dataRef);
    }

    /**
     * Async fetch with full options support.
     * Calls __zx_fetch_complete when done.
     */
    fetchAsync(
        urlPtr: number,
        urlLen: number,
        methodPtr: number,
        methodLen: number,
        headersPtr: number,
        headersLen: number,
        bodyPtr: number,
        bodyLen: number,
        timeoutMs: number,
        fetchId: bigint
    ): void {
        const url = readString(urlPtr, urlLen);
        const method = methodLen > 0 ? readString(methodPtr, methodLen) : 'GET';
        const headersJson = headersLen > 0 ? readString(headersPtr, headersLen) : '{}';
        const body = bodyLen > 0 ? readString(bodyPtr, bodyLen) : undefined;

        let headers: Record<string, string> = {};
        try {
            headers = JSON.parse(headersJson);
        } catch {
            for (const line of headersJson.split('\n')) {
                const colonIdx = line.indexOf(':');
                if (colonIdx > 0) {
                    headers[line.slice(0, colonIdx)] = line.slice(colonIdx + 1);
                }
            }
        }

        const controller = new AbortController();
        const timeout = timeoutMs > 0 ? setTimeout(() => controller.abort(), timeoutMs) : null;

        const fetchOptions: RequestInit = {
            method,
            headers: Object.keys(headers).length > 0 ? headers : undefined,
            body: method !== 'GET' && method !== 'HEAD' ? body : undefined,
            signal: controller.signal,
        };

        fetch(url, fetchOptions)
            .then(async (response) => {
                if (timeout) clearTimeout(timeout);
                const text = await response.text();
                this._notifyFetchComplete(fetchId, response.status, text, false);
            })
            .catch((error) => {
                if (timeout) clearTimeout(timeout);
                const isAbort = error.name === 'AbortError';
                const errorMsg = isAbort ? 'Request timeout' : (error.message ?? 'Fetch failed');
                this._notifyFetchComplete(fetchId, 0, errorMsg, true);
            });
    }

    /** Notify WASM that a fetch completed */
    protected _notifyFetchComplete(fetchId: bigint, statusCode: number, body: string, isError: boolean): void {
        const handler = this.#fetchCompleteHandler;
        const encoded = textEncoder.encode(body);
        const ptr = this._alloc(encoded.length);
        writeBytes(ptr, encoded);
        invokeWasmExport(handler, fetchId, statusCode, ptr, encoded.length, isError ? 1 : 0);
    }

    /** Set a timeout and callback when it fires */
    setTimeout(callbackId: bigint, delayMs: number): void {
        setTimeout(() => {
            this.#invoke(CallbackType.Timeout, callbackId, null);
        }, delayMs);
    }

    /** Set an interval and callback each time it fires */
    setInterval(callbackId: bigint, intervalMs: number): void {
        const handle = setInterval(() => {
            this.#invoke(CallbackType.Interval, callbackId, null);
        }, intervalMs) as unknown as number;
        this.#intervals.set(callbackId, handle);
    }

    /** Clear an interval */
    clearInterval(callbackId: bigint): void {
        const handle = this.#intervals.get(callbackId);
        if (handle !== undefined) {
            clearInterval(handle);
            this.#intervals.delete(callbackId);
        }
    }

    dispose(): void {
        for (const handle of this.#intervals.values()) {
            clearInterval(handle);
        }
        this.#intervals.clear();
    }

    /** Write a string to WASM memory, returning pointer and length */
    protected _writeStringToWasm(str: string): { ptr: number; len: number } {
        return this._writeBytesToWasm(textEncoder.encode(str));
    }

    protected _writeBytesToWasm(data: Uint8Array): { ptr: number; len: number } {
        const ptr = this._alloc(data.length);
        writeBytes(ptr, data);
        return { ptr, len: data.length };
    }

    /** Log a message from WASM at the given level (0=error, 1=warn, 2=info, 3=debug) */
    static log(level: number, ptr: number, len: number): void {
        const msg = textDecoder.decode(getMemoryView().subarray(ptr, ptr + len));
        switch (level) {
            case 0: console.error(msg); break;
            case 1: console.warn(msg); break;
            case 3: console.debug(msg); break;
            default: console.log(msg); break;
        }
    }

    /**
     * Create the core import object for WASM instantiation.
     * Includes only environment-agnostic bindings: log, fetch, and timers.
     * Use ZxBridge.createImportObject (from wasm/index.ts) in browser contexts
     * to additionally include DOM and WebSocket bindings.
     */
    static createImportObject(bridgeRef: { current: ZxBridgeCore | null }): WebAssembly.Imports {
        return {
            ...jsz.importObject(),
            __zx: {
                _log: (level: number, ptr: number, len: number) => ZxBridgeCore.log(level, ptr, len),
                _fetchAsync: (
                    urlPtr: number,
                    urlLen: number,
                    methodPtr: number,
                    methodLen: number,
                    headersPtr: number,
                    headersLen: number,
                    bodyPtr: number,
                    bodyLen: number,
                    timeoutMs: number,
                    fetchId: bigint
                ) => {
                    bridgeRef.current?.fetchAsync(
                        urlPtr, urlLen,
                        methodPtr, methodLen,
                        headersPtr, headersLen,
                        bodyPtr, bodyLen,
                        timeoutMs,
                        fetchId
                    );
                },
                _setTimeout: (callbackId: bigint, delayMs: number) => {
                    bridgeRef.current?.setTimeout(callbackId, delayMs);
                },
                _setInterval: (callbackId: bigint, intervalMs: number) => {
                    bridgeRef.current?.setInterval(callbackId, intervalMs);
                },
                _clearInterval: (callbackId: bigint) => {
                    bridgeRef.current?.clearInterval(callbackId);
                },
            },
        };
    }
}
