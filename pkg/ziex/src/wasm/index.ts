import { ZigJS } from "../../../../vendor/jsz/js/src";

/**
 * ZX Client Bridge - Unified JS↔WASM communication layer
 * Handles events, fetch, WebSocket, timers, and other async callbacks using jsz
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
type CallbackHandler = (callbackType: number, id: bigint, dataRef: bigint) => void;
type FetchCompleteHandler = (fetchId: bigint, statusCode: number, bodyPtr: number, bodyLen: number, isError: number) => void;

// WebSocket callback handler types
type WsOnOpenHandler = (wsId: bigint, protocolPtr: number, protocolLen: number) => void;
type WsOnMessageHandler = (wsId: bigint, dataPtr: number, dataLen: number, isBinary: number) => void;
type WsOnErrorHandler = (wsId: bigint, msgPtr: number, msgLen: number) => void;
type WsOnCloseHandler = (wsId: bigint, code: number, reasonPtr: number, reasonLen: number, wasClean: number) => void;

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

/** Read a string from WASM memory */
function readString(ptr: number, len: number): string {
    const memory = new Uint8Array(jsz.memory!.buffer);
    return new TextDecoder().decode(memory.slice(ptr, ptr + len));
}

/** Write bytes to WASM memory at a specific location */
function writeBytes(ptr: number, data: Uint8Array): void {
    const memory = new Uint8Array(jsz.memory!.buffer);
    memory.set(data, ptr);
}

/** ZX Bridge - provides JS APIs that callback into WASM */
export class ZxBridge {
    #exports: WebAssembly.Exports;
    #intervals: Map<bigint, number> = new Map();
    #websockets: Map<bigint, WebSocket> = new Map();

    constructor(exports: WebAssembly.Exports) {
        this.#exports = exports;
    }

    get #alloc(): ((size: number) => number) {
        return this.#exports.__zx_alloc as ((size: number) => number);
    }

    get #handler(): CallbackHandler | undefined {
        return this.#exports.__zx_cb as CallbackHandler | undefined;
    }

    get #fetchCompleteHandler(): FetchCompleteHandler {
        return this.#exports.__zx_fetch_complete as FetchCompleteHandler;
    }

    // WebSocket callback handlers
    get #wsOnOpenHandler(): WsOnOpenHandler | undefined {
        return this.#exports.__zx_ws_onopen as WsOnOpenHandler | undefined;
    }

    get #wsOnMessageHandler(): WsOnMessageHandler | undefined {
        return this.#exports.__zx_ws_onmessage as WsOnMessageHandler | undefined;
    }

    get #wsOnErrorHandler(): WsOnErrorHandler | undefined {
        return this.#exports.__zx_ws_onerror as WsOnErrorHandler | undefined;
    }

    get #wsOnCloseHandler(): WsOnCloseHandler | undefined {
        return this.#exports.__zx_ws_onclose as WsOnCloseHandler | undefined;
    }

    /** Invoke the unified callback handler */
    #invoke(type: CallbackTypeValue, id: bigint, data: any): void {
        const handler = this.#handler;
        if (!handler) {
            console.warn('__zx_cb not exported from WASM');
            return;
        }
        const dataRef = storeValueGetRef(data);
        handler(type, id, dataRef);
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

        // Parse headers from JSON
        let headers: Record<string, string> = {};
        try {
            headers = JSON.parse(headersJson);
        } catch {
            // Fallback: try line-based format "name:value\n"
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
                this.#notifyFetchComplete(fetchId, response.status, text, false);
            })
            .catch((error) => {
                if (timeout) clearTimeout(timeout);
                const isAbort = error.name === 'AbortError';
                const errorMsg = isAbort ? 'Request timeout' : (error.message ?? 'Fetch failed');
                this.#notifyFetchComplete(fetchId, 0, errorMsg, true);
            });
    }

    /** Notify WASM that a fetch completed */
    #notifyFetchComplete(fetchId: bigint, statusCode: number, body: string, isError: boolean): void {
        const handler = this.#fetchCompleteHandler;

        // Write the body to WASM memory
        const encoded = new TextEncoder().encode(body);
        
        // Allocate memory for body
        const ptr = this.#alloc(encoded.length);

        writeBytes(ptr, encoded);
        
        handler(fetchId, statusCode, ptr, encoded.length, isError ? 1 : 0);
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

    // ========================================================================
    // WebSocket API
    // ========================================================================

    /**
     * Create and connect a WebSocket.
     * Calls __zx_ws_onopen, __zx_ws_onmessage, __zx_ws_onerror, __zx_ws_onclose.
     */
    wsConnect(
        wsId: bigint,
        urlPtr: number,
        urlLen: number,
        protocolsPtr: number,
        protocolsLen: number
    ): void {
        const url = readString(urlPtr, urlLen);
        const protocolsStr = protocolsLen > 0 ? readString(protocolsPtr, protocolsLen) : '';
        const protocols = protocolsStr ? protocolsStr.split(',').map(p => p.trim()).filter(Boolean) : undefined;

        try {
            const ws = protocols && protocols.length > 0 
                ? new WebSocket(url, protocols)
                : new WebSocket(url);

            ws.binaryType = 'arraybuffer';

            ws.onopen = () => {
                const handler = this.#wsOnOpenHandler;
                if (!handler) return;

                // Write protocol to WASM memory
                const protocol = ws.protocol || '';
                const { ptr, len } = this.#writeStringToWasm(protocol);
                handler(wsId, ptr, len);
            };

            ws.onmessage = (event: MessageEvent) => {
                const handler = this.#wsOnMessageHandler;
                if (!handler) return;

                const isBinary = event.data instanceof ArrayBuffer;
                let data: Uint8Array;

                if (isBinary) {
                    data = new Uint8Array(event.data as ArrayBuffer);
                } else {
                    data = new TextEncoder().encode(event.data as string);
                }

                const { ptr, len } = this.#writeBytesToWasm(data);
                handler(wsId, ptr, len, isBinary ? 1 : 0);
            };

            ws.onerror = (event: Event) => {
                const handler = this.#wsOnErrorHandler;
                if (!handler) return;

                const msg = 'WebSocket error';
                const { ptr, len } = this.#writeStringToWasm(msg);
                handler(wsId, ptr, len);
            };

            ws.onclose = (event: CloseEvent) => {
                const handler = this.#wsOnCloseHandler;
                if (!handler) return;

                const reason = event.reason || '';
                const { ptr, len } = this.#writeStringToWasm(reason);
                handler(wsId, event.code, ptr, len, event.wasClean ? 1 : 0);

                // Clean up
                this.#websockets.delete(wsId);
            };

            this.#websockets.set(wsId, ws);
        } catch (error) {
            // Connection failed immediately
            const handler = this.#wsOnErrorHandler;
            if (handler) {
                const msg = error instanceof Error ? error.message : 'WebSocket connection failed';
                const { ptr, len } = this.#writeStringToWasm(msg);
                handler(wsId, ptr, len);
            }
        }
    }

    /** Send data over WebSocket */
    wsSend(wsId: bigint, dataPtr: number, dataLen: number, isBinary: number): void {
        const ws = this.#websockets.get(wsId);
        if (!ws || ws.readyState !== WebSocket.OPEN) return;

        const memory = new Uint8Array(jsz.memory!.buffer);
        const data = memory.slice(dataPtr, dataPtr + dataLen);

        if (isBinary) {
            ws.send(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
        } else {
            ws.send(new TextDecoder().decode(data));
        }
    }

    /** Close WebSocket connection */
    wsClose(wsId: bigint, code: number, reasonPtr: number, reasonLen: number): void {
        const ws = this.#websockets.get(wsId);
        if (!ws) return;

        const reason = reasonLen > 0 ? readString(reasonPtr, reasonLen) : undefined;

        try {
            if (reason) {
                ws.close(code, reason);
            } else {
                ws.close(code);
            }
        } catch {
            // Invalid code or reason, just force close
            ws.close();
        }
    }

    /** Write a string to WASM memory, returning pointer and length */
    #writeStringToWasm(str: string): { ptr: number; len: number } {
        const encoded = new TextEncoder().encode(str);
        return this.#writeBytesToWasm(encoded);
    }

    #writeBytesToWasm(data: Uint8Array): { ptr: number; len: number } {
        const ptr = this.#alloc(data.length);
        writeBytes(ptr, data);
        return { ptr, len: data.length };
    }

    /** Handle a DOM event (called by event delegation) */
    eventbridge(velementId: bigint, eventTypeId: number, event: Event): void {
        const eventRef = storeValueGetRef(event);
        const eventbridge = this.#exports.__zx_eventbridge as ((velementId: bigint, eventTypeId: number, eventRef: bigint) => void) | undefined;
        if (eventbridge) eventbridge(velementId, eventTypeId, eventRef);
    }

    /** Create the import object for WASM instantiation */
    static createImportObject(bridgeRef: { current: ZxBridge | null }): WebAssembly.Imports {
        return {
            ...jsz.importObject(),
            __zx: {
                // Async fetch with full options
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
                // WebSocket API
                _wsConnect: (
                    wsId: bigint,
                    urlPtr: number,
                    urlLen: number,
                    protocolsPtr: number,
                    protocolsLen: number
                ) => {
                    bridgeRef.current?.wsConnect(wsId, urlPtr, urlLen, protocolsPtr, protocolsLen);
                },
                _wsSend: (wsId: bigint, dataPtr: number, dataLen: number, isBinary: number) => {
                    bridgeRef.current?.wsSend(wsId, dataPtr, dataLen, isBinary);
                },
                _wsClose: (wsId: bigint, code: number, reasonPtr: number, reasonLen: number) => {
                    bridgeRef.current?.wsClose(wsId, code, reasonPtr, reasonLen);
                },
                _ce: (id: number) => {
                    const tagName = TAG_NAMES[id] as string;
                    // SVG elements start at index SVG_TAG_START_INDEX and need createElementNS
                    const el = id >= SVG_TAG_START_INDEX
                        ? document.createElementNS('http://www.w3.org/2000/svg', tagName)
                        : document.createElement(tagName);
                    return storeValueGetRef(el);
                },
            },
        };
    }
}

// Index where SVG tags start in TAG_NAMES array
const SVG_TAG_START_INDEX = 140;

// Event delegation constants
const TAG_NAMES = [
    'aside',
    'fragment',
    'iframe',
    'slot',
    'img',
    'html',
    'base',
    'head',
    'link',
    'meta',
    'script',
    'style',
    'title',
    'address',
    'article',
    'body',
    'h1',
    'h6',
    'footer',
    'header',
    'h2',
    'h3',
    'h4',
    'h5',
    'hgroup',
    'nav',
    'section',
    'dd',
    'dl',
    'dt',
    'div',
    'figcaption',
    'figure',
    'hr',
    'li',
    'ol',
    'ul',
    'menu',
    'main',
    'p',
    'picture',
    'pre',
    'a',
    'abbr',
    'b',
    'bdi',
    'bdo',
    'br',
    'cite',
    'code',
    'data',
    'time',
    'dfn',
    'em',
    'i',
    'kbd',
    'mark',
    'q',
    'blockquote',
    'rp',
    'ruby',
    'rt',
    'rtc',
    'rb',
    's',
    'del',
    'ins',
    'samp',
    'small',
    'span',
    'strong',
    'sub',
    'sup',
    'u',
    'var',
    'wbr',
    'area',
    'map',
    'audio',
    'source',
    'track',
    'video',
    'embed',
    'object',
    'param',
    'canvas',
    'noscript',
    'caption',
    'table',
    'col',
    'colgroup',
    'tbody',
    'tr',
    'thead',
    'tfoot',
    'td',
    'th',
    'button',
    'datalist',
    'option',
    'fieldset',
    'label',
    'form',
    'input',
    'keygen',
    'legend',
    'meter',
    'optgroup',
    'select',
    'output',
    'progress',
    'textarea',
    'details',
    'dialog',
    'menuitem',
    'summary',
    'content',
    'element',
    'shadow',
    'template',
    'acronym',
    'applet',
    'basefont',
    'font',
    'big',
    'blink',
    'center',
    'command',
    'dir',
    'frame',
    'frameset',
    'isindex',
    'listing',
    'marquee',
    'noembed',
    'plaintext',
    'spacer',
    'strike',
    'tt',
    'xmp',
    // SVG Tags
    'animate',
    'animateMotion',
    'animateTransform',
    'circle',
    'clipPath',
    'defs',
    'desc',
    'ellipse',
    'feBlend',
    'feColorMatrix',
    'feComponentTransfer',
    'feComposite',
    'feConvolveMatrix',
    'feDiffuseLighting',
    'feDisplacementMap',
    'feDistantLight',
    'feDropShadow',
    'feFlood',
    'feFuncA',
    'feFuncB',
    'feFuncG',
    'feFuncR',
    'feGaussianBlur',
    'feImage',
    'feMerge',
    'feMergeNode',
    'feMorphology',
    'feOffset',
    'fePointLight',
    'feSpecularLighting',
    'feSpotLight',
    'feTile',
    'feTurbulence',
    'filter',
    'foreignObject',
    'g',
    'image',
    'line',
    'linearGradient',
    'marker',
    'mask',
    'metadata',
    'mpath',
    'path',
    'pattern',
    'polygon',
    'polyline',
    'radialGradient',
    'rect',
    'set',
    'stop',
    'svg',
    'switch',
    'symbol',
    'text',
    'textPath',
    'tspan',
    'use',
    'view',
] as const;



const DELEGATED_EVENTS = [
    'click', 'dblclick',
    'input', 'change', 'submit',
    'focus', 'blur',
    'keydown', 'keyup', 'keypress',
    'mouseenter', 'mouseleave',
    'mousedown', 'mouseup', 'mousemove',
    'touchstart', 'touchend', 'touchmove',
    'scroll',
] as const;

type DelegatedEvent = typeof DELEGATED_EVENTS[number];

const EVENT_TYPE_MAP: Record<DelegatedEvent, number> = {
    'click': 0, 'dblclick': 1, 'input': 2, 'change': 3, 'submit': 4,
    'focus': 5, 'blur': 6, 'keydown': 7, 'keyup': 8, 'keypress': 9,
    'mouseenter': 10, 'mouseleave': 11, 'mousedown': 12, 'mouseup': 13,
    'mousemove': 14, 'touchstart': 15, 'touchend': 16, 'touchmove': 17,
    'scroll': 18,
};

/** Initialize event delegation */
export function initEventDelegation(bridge: ZxBridge, rootSelector: string = 'body'): void {
    const root = document.querySelector(rootSelector);
    if (!root) return;

    for (const eventType of DELEGATED_EVENTS) {
        root.addEventListener(eventType, (event: Event) => {
            let target = event.target as HTMLElement | null;

            while (target && target !== document.body) {
                const zxRef = (target as any).__zx_ref;
                if (zxRef !== undefined) {
                    bridge.eventbridge(BigInt(zxRef), EVENT_TYPE_MAP[eventType] ?? 0, event);
                    break;
                }
                target = target.parentElement;
            }
        }, { passive: eventType.startsWith('touch') || eventType === 'scroll' });
    }
}

export type InitOptions = {
    url?: string;
    eventDelegationRoot?: string;
    importObject?: WebAssembly.Imports;
};

const DEFAULT_URL = "/assets/main.wasm";

/** Initialize WASM with the ZX Bridge */
export async function init(options: InitOptions = {}): Promise<{ source: WebAssembly.WebAssemblyInstantiatedSource; bridge: ZxBridge }> {
    const url = options.url ?? DEFAULT_URL;
    
    // Bridge reference for import object (will be set after instantiation)
    const bridgeRef: { current: ZxBridge | null } = { current: null };
    
    const importObject = Object.assign(
        {},
        ZxBridge.createImportObject(bridgeRef),
        options.importObject
    );
    
    const source = await WebAssembly.instantiateStreaming(fetch(url), importObject);
    const { instance } = source;

    jsz.memory = instance.exports.memory as WebAssembly.Memory;
    
    const bridge = new ZxBridge(instance.exports);
    bridgeRef.current = bridge;

    initEventDelegation(bridge, options.eventDelegationRoot ?? 'body');

    // Call main to initiate the client side rendering
    const main = instance.exports.mainClient;
    if (typeof main === 'function') main();

    return { source, bridge };
}


/** Initialize WASM with the ZX Bridge */
export async function edge(options: InitOptions = {}): Promise<{ source: WebAssembly.WebAssemblyInstantiatedSource; bridge: ZxBridge }> {
    const url = options.url ?? DEFAULT_URL;
    
    // Bridge reference for import object (will be set after instantiation)
    const bridgeRef: { current: ZxBridge | null } = { current: null };
    
    const importObject = Object.assign(
        {},
        ZxBridge.createImportObject(bridgeRef),
        options.importObject
    );
    
    const source = await WebAssembly.instantiateStreaming(fetch(url), importObject);
    const { instance } = source;

    jsz.memory = instance.exports.memory as WebAssembly.Memory;
    
    const bridge = new ZxBridge(instance.exports);
    bridgeRef.current = bridge;

    initEventDelegation(bridge, options.eventDelegationRoot ?? 'body');

    // Call main to initiate the client side rendering
    const main = instance.exports.main;
    if (typeof main === 'function') main();

    return { source, bridge };
}


// Global type declarations
declare global {
    interface HTMLElement {
        __zx_ref?: number;
    }
}
