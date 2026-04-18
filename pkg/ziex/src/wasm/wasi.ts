/**
 * WASI/edge WASM bridge - zero dependencies on ZigJS (jsz) or browser globals.
 *
 * Import this (and only this) from edge/server runtimes. It provides the
 * minimal __zx import namespace needed by server-side WASM: log, fetch, and
 * timers. The jsz importObject is intentionally omitted - the server binary
 * does not use jsz value-passing.
 */

type FetchCompleteHandler = (fetchId: bigint, statusCode: number, bodyPtr: number, bodyLen: number, isError: number) => void;

const decoder = new TextDecoder();
const encoder = new TextEncoder();

export class ZxWasiBridge {
    readonly #alloc: (size: number) => number;
    readonly #fetchCompleteHandler: FetchCompleteHandler;
    readonly #memory: WebAssembly.Memory;
    readonly #cb: ((type: number, id: bigint, data: bigint) => void) | undefined;
    readonly #intervals: Map<bigint, ReturnType<typeof setInterval>> = new Map();

    // Cached memory view - invalidated when the WASM buffer grows.
    #memView: Uint8Array | null = null;
    #memBuf: ArrayBufferLike | null = null;

    constructor(exports: WebAssembly.Exports) {
        this.#memory = exports.memory as WebAssembly.Memory;
        this.#alloc = exports.__zx_alloc as (size: number) => number;
        this.#fetchCompleteHandler = exports.__zx_fetch_complete as FetchCompleteHandler;
        this.#cb = exports.__zx_cb as ((type: number, id: bigint, data: bigint) => void) | undefined;
    }

    #view(): Uint8Array {
        const buf = this.#memory.buffer;
        if (buf !== this.#memBuf) {
            this.#memBuf = buf;
            this.#memView = new Uint8Array(buf);
        }
        return this.#memView!;
    }

    #readString(ptr: number, len: number): string {
        return decoder.decode(this.#view().subarray(ptr, ptr + len));
    }

    #writeBytes(ptr: number, data: Uint8Array): void {
        this.#view().set(data, ptr);
    }

    log(level: number, ptr: number, len: number): void {
        const msg = decoder.decode(this.#view().subarray(ptr, ptr + len));
        switch (level) {
            case 0: console.error(msg); break;
            case 1: console.warn(msg); break;
            case 3: console.debug(msg); break;
            default: console.log(msg); break;
        }
    }

    fetchAsync(
        urlPtr: number, urlLen: number,
        methodPtr: number, methodLen: number,
        headersPtr: number, headersLen: number,
        bodyPtr: number, bodyLen: number,
        timeoutMs: number,
        fetchId: bigint
    ): void {
        const url = this.#readString(urlPtr, urlLen);
        const method = methodLen > 0 ? this.#readString(methodPtr, methodLen) : 'GET';
        const headersJson = headersLen > 0 ? this.#readString(headersPtr, headersLen) : '{}';
        const body = bodyLen > 0 ? this.#readString(bodyPtr, bodyLen) : undefined;

        let headers: Record<string, string> = {};
        try {
            headers = JSON.parse(headersJson);
        } catch {
            for (const line of headersJson.split('\n')) {
                const i = line.indexOf(':');
                if (i > 0) headers[line.slice(0, i)] = line.slice(i + 1);
            }
        }

        const controller = new AbortController();
        const timeout = timeoutMs > 0 ? setTimeout(() => controller.abort(), timeoutMs) : null;

        fetch(url, {
            method,
            headers: Object.keys(headers).length > 0 ? headers : undefined,
            body: method !== 'GET' && method !== 'HEAD' ? body : undefined,
            signal: controller.signal,
        })
            .then(async (res) => {
                if (timeout) clearTimeout(timeout);
                this.#notifyFetchComplete(fetchId, res.status, await res.text(), false);
            })
            .catch((err: Error) => {
                if (timeout) clearTimeout(timeout);
                const msg = err.name === 'AbortError' ? 'Request timeout' : (err.message ?? 'Fetch failed');
                this.#notifyFetchComplete(fetchId, 0, msg, true);
            });
    }

    #notifyFetchComplete(fetchId: bigint, status: number, body: string, isError: boolean): void {
        const encoded = encoder.encode(body);
        const ptr = this.#alloc(encoded.length);
        this.#writeBytes(ptr, encoded);
        this.#fetchCompleteHandler(fetchId, status, ptr, encoded.length, isError ? 1 : 0);
    }

    setTimeout(callbackId: bigint, delayMs: number): void {
        setTimeout(() => this.#cb?.(3 /* Timeout */, callbackId, 0n), delayMs);
    }

    setInterval(callbackId: bigint, intervalMs: number): void {
        const handle = setInterval(() => this.#cb?.(4 /* Interval */, callbackId, 0n), intervalMs);
        this.#intervals.set(callbackId, handle);
    }

    clearInterval(callbackId: bigint): void {
        const handle = this.#intervals.get(callbackId);
        if (handle !== undefined) {
            clearInterval(handle);
            this.#intervals.delete(callbackId);
        }
    }

    /**
     * Create the WASI import object for WASM instantiation.
     *
     * Returns only the `__zx` namespace (log, fetch, timers).
     * Does NOT include jsz.importObject() - the server binary does not use jsz.
     */
    static createImportObject(bridgeRef: { current: ZxWasiBridge | null }): { __zx: Record<string, unknown> } {
        return {
            __zx: {
                _log: (level: number, ptr: number, len: number) => {
                    bridgeRef.current?.log(level, ptr, len);
                },
                _fetchAsync: (
                    urlPtr: number, urlLen: number,
                    methodPtr: number, methodLen: number,
                    headersPtr: number, headersLen: number,
                    bodyPtr: number, bodyLen: number,
                    timeoutMs: number,
                    fetchId: bigint
                ) => {
                    bridgeRef.current?.fetchAsync(
                        urlPtr, urlLen, methodPtr, methodLen,
                        headersPtr, headersLen, bodyPtr, bodyLen,
                        timeoutMs, fetchId
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
