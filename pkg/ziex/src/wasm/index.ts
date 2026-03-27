export {
    CallbackType,
    jsz,
    storeValueGetRef,
    textDecoder,
    textEncoder,
    getMemoryView,
    readString,
    writeBytes,
    ZxBridgeCore,
} from "./core";
export type { CallbackTypeValue } from "./core";

import {
    ZxBridgeCore,
    jsz,
    storeValueGetRef,
    readString,
    writeBytes,
    textDecoder,
    textEncoder,
    getMemoryView,
} from "./core";
import type {
    WsOnOpenHandler,
    WsOnMessageHandler,
    WsOnErrorHandler,
    WsOnCloseHandler,
} from "./core";

/**
 * Browser ZX Bridge — extends ZxBridgeCore with DOM, WebSocket, and form-action support.
 * Import this from environments that have access to browser globals.
 * For edge runtimes, import ZxBridgeCore from ./core instead.
 */
export class ZxBridge extends ZxBridgeCore {
    #websockets: Map<bigint, WebSocket> = new Map();

    readonly #wsOnOpenHandler: WsOnOpenHandler | undefined;
    readonly #wsOnMessageHandler: WsOnMessageHandler | undefined;
    readonly #wsOnErrorHandler: WsOnErrorHandler | undefined;
    readonly #wsOnCloseHandler: WsOnCloseHandler | undefined;
    readonly #eventbridge: ((velementId: bigint, eventTypeId: number, eventRef: bigint) => void) | undefined;

    constructor(exports: WebAssembly.Exports) {
        super(exports);
        this.#wsOnOpenHandler = exports.__zx_ws_onopen as WsOnOpenHandler | undefined;
        this.#wsOnMessageHandler = exports.__zx_ws_onmessage as WsOnMessageHandler | undefined;
        this.#wsOnErrorHandler = exports.__zx_ws_onerror as WsOnErrorHandler | undefined;
        this.#wsOnCloseHandler = exports.__zx_ws_onclose as WsOnCloseHandler | undefined;
        this.#eventbridge = exports.__zx_eventbridge as ((velementId: bigint, eventTypeId: number, eventRef: bigint) => void) | undefined;
    }

    /** Submit a form action with bound-state round-trip. */
    submitFormActionAsync(form: HTMLFormElement, statesJson: string, fetchId: bigint): void {
        const formData = new FormData(form);
        formData.append('__$states', statesJson);
        fetch(window.location.href, {
            method: 'POST',
            headers: { 'X-ZX-Action': '1' },
            body: formData,
        })
        .then(async (response) => {
            const text = await response.text();
            this._notifyFetchComplete(fetchId, response.status, text, false);
        })
        .catch((error: unknown) => {
            const msg = error instanceof Error ? error.message : 'Fetch failed';
            this._notifyFetchComplete(fetchId, 0, msg, true);
        });
    }

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
                const protocol = ws.protocol || '';
                const { ptr, len } = this._writeStringToWasm(protocol);
                handler(wsId, ptr, len);
            };

            ws.onmessage = (event: MessageEvent) => {
                const handler = this.#wsOnMessageHandler;
                if (!handler) return;
                const isBinary = event.data instanceof ArrayBuffer;
                const data: Uint8Array = isBinary
                    ? new Uint8Array(event.data as ArrayBuffer)
                    : textEncoder.encode(event.data as string);
                const { ptr, len } = this._writeBytesToWasm(data);
                handler(wsId, ptr, len, isBinary ? 1 : 0);
            };

            ws.onerror = (_event: Event) => {
                const handler = this.#wsOnErrorHandler;
                if (!handler) return;
                const { ptr, len } = this._writeStringToWasm('WebSocket error');
                handler(wsId, ptr, len);
            };

            ws.onclose = (event: CloseEvent) => {
                const handler = this.#wsOnCloseHandler;
                if (!handler) return;
                const reason = event.reason || '';
                const { ptr, len } = this._writeStringToWasm(reason);
                handler(wsId, event.code, ptr, len, event.wasClean ? 1 : 0);
                this.#websockets.delete(wsId);
            };

            this.#websockets.set(wsId, ws);
        } catch (error) {
            const handler = this.#wsOnErrorHandler;
            if (handler) {
                const msg = error instanceof Error ? error.message : 'WebSocket connection failed';
                const { ptr, len } = this._writeStringToWasm(msg);
                handler(wsId, ptr, len);
            }
        }
    }

    /** Send data over WebSocket */
    wsSend(wsId: bigint, dataPtr: number, dataLen: number, isBinary: number): void {
        const ws = this.#websockets.get(wsId);
        if (!ws || ws.readyState !== WebSocket.OPEN) return;
        const memory = getMemoryView();
        if (isBinary) {
            ws.send(memory.slice(dataPtr, dataPtr + dataLen));
        } else {
            ws.send(textDecoder.decode(memory.subarray(dataPtr, dataPtr + dataLen)));
        }
    }

    /** Close WebSocket connection */
    wsClose(wsId: bigint, code: number, reasonPtr: number, reasonLen: number): void {
        const ws = this.#websockets.get(wsId);
        if (!ws) return;
        const reason = reasonLen > 0 ? readString(reasonPtr, reasonLen) : undefined;
        try {
            if (reason) ws.close(code, reason);
            else ws.close(code);
        } catch {
            ws.close();
        }
    }

    override dispose(): void {
        super.dispose();
        for (const ws of this.#websockets.values()) {
            try {
                ws.close();
            } catch {
                // Ignore shutdown races during hot-reinit.
            }
        }
        this.#websockets.clear();
    }

    /** Handle a DOM event (called by event delegation) */
    eventbridge(velementId: bigint, eventTypeId: number, event: Event): void {
        if (!this.#eventbridge) return;
        const eventRef = storeValueGetRef(event);
        this.#eventbridge(velementId, eventTypeId, eventRef);
    }

    /** Create the full browser import object for WASM instantiation (includes DOM + WebSocket). */
    static override createImportObject(bridgeRef: { current: ZxBridge | null }): WebAssembly.Imports {
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
                // ── Direct DOM externs ──────────────────────────────────────────────────
                _ce: (id: number, vnodeId: bigint): bigint => {
                    const tagName = TAG_NAMES[id] as string;
                    const el = id >= SVG_TAG_START_INDEX
                        ? document.createElementNS('http://www.w3.org/2000/svg', tagName)
                        : document.createElement(tagName);
                    (el as any).__zx_ref = Number(vnodeId);
                    domNodes.set(vnodeId, el);
                    return storeValueGetRef(el);
                },
                _ct: (ptr: number, len: number, vnodeId: bigint): bigint => {
                    const text = readString(ptr, len);
                    const node = document.createTextNode(text);
                    (node as any).__zx_ref = Number(vnodeId);
                    domNodes.set(vnodeId, node);
                    return storeValueGetRef(node);
                },
                _sa: (vnodeId: bigint, namePtr: number, nameLen: number, valPtr: number, valLen: number) => {
                    (domNodes.get(vnodeId) as Element | undefined)
                        ?.setAttribute(readString(namePtr, nameLen), readString(valPtr, valLen));
                },
                _ra: (vnodeId: bigint, namePtr: number, nameLen: number) => {
                    (domNodes.get(vnodeId) as Element | undefined)
                        ?.removeAttribute(readString(namePtr, nameLen));
                },
                _snv: (vnodeId: bigint, ptr: number, len: number) => {
                    const node = domNodes.get(vnodeId);
                    if (node) node.nodeValue = readString(ptr, len);
                },
                _ac: (parentId: bigint, childId: bigint) => {
                    const parent = domNodes.get(parentId);
                    const child = domNodes.get(childId);
                    if (parent && child) parent.appendChild(child);
                },
                _ib: (parentId: bigint, childId: bigint, refId: bigint) => {
                    const parent = domNodes.get(parentId);
                    const child = domNodes.get(childId);
                    const ref = domNodes.get(refId) ?? null;
                    if (parent && child) parent.insertBefore(child, ref);
                },
                _rc: (parentId: bigint, childId: bigint) => {
                    const parent = domNodes.get(parentId);
                    const child = domNodes.get(childId);
                    if (parent && child) {
                        parent.removeChild(child);
                        cleanupDomNodes(child);
                    }
                },
                _rpc: (parentId: bigint, newId: bigint, oldId: bigint) => {
                    const parent = domNodes.get(parentId);
                    const newChild = domNodes.get(newId);
                    const oldChild = domNodes.get(oldId);
                    if (parent && newChild && oldChild) {
                        parent.replaceChild(newChild, oldChild);
                        cleanupDomNodes(oldChild);
                    }
                },
                _getLocationHref: (bufPtr: number, bufLen: number): number => {
                    const bytes = textEncoder.encode(window.location.href);
                    const len = Math.min(bytes.length, bufLen);
                    writeBytes(bufPtr, bytes.subarray(0, len));
                    return len;
                },
                _getFormData: (vnodeId: bigint, bufPtr: number, bufLen: number): number => {
                    const form = domNodes.get(vnodeId) as HTMLFormElement | undefined;
                    if (!form || !(form instanceof HTMLFormElement)) return 0;
                    const formData = new FormData(form);
                    const urlEncoded = new URLSearchParams(formData as any).toString();
                    const bytes = textEncoder.encode(urlEncoded);
                    const len = Math.min(bytes.length, bufLen);
                    writeBytes(bufPtr, bytes.subarray(0, len));
                    return len;
                },
                _submitFormAction: (vnodeId: bigint): void => {
                    const form = domNodes.get(vnodeId) as HTMLFormElement | undefined;
                    if (!form || !(form instanceof HTMLFormElement)) return;
                    const formData = new FormData(form);
                    fetch(window.location.href, {
                        method: 'POST',
                        headers: { 'X-ZX-Action': '1' },
                        body: formData,
                    }).catch(() => {});
                },
                _submitFormActionAsync: (vnodeId: bigint, statesPtr: number, statesLen: number, fetchId: bigint): void => {
                    const form = domNodes.get(vnodeId) as HTMLFormElement | undefined;
                    if (!form || !(form instanceof HTMLFormElement)) return;
                    const statesJson = statesLen > 0 ? readString(statesPtr, statesLen) : '[]';
                    bridgeRef.current?.submitFormActionAsync(form, statesJson, fetchId);
                },
            },
        };
    }
}

/** JS-side DOM node registry: vnode_id → Node. Mirrors the live DOM tree. */
const domNodes = new Map<bigint, Node>();

/** Recursively remove a node subtree from domNodes. */
function cleanupDomNodes(node: Node): void {
    const ref = (node as any).__zx_ref;
    if (ref !== undefined) domNodes.delete(BigInt(ref));
    const children = node.childNodes;
    for (let i = 0; i < children.length; i++) cleanupDomNodes(children[i]!);
}

// Index where SVG tags start in TAG_NAMES array
const SVG_TAG_START_INDEX = 140;

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
export function initEventDelegation(bridge: ZxBridge, rootSelector: string = 'body'): () => void {
    const root = document.querySelector(rootSelector);
    if (!root) return () => {};

    const removers: Array<() => void> = [];

    for (const eventType of DELEGATED_EVENTS) {
        const listener = (event: Event) => {
            let target = event.target as HTMLElement | null;
            while (target && target !== document.body) {
                const zxRef = (target as any).__zx_ref;
                if (zxRef !== undefined) {
                    bridge.eventbridge(BigInt(zxRef), EVENT_TYPE_MAP[eventType] ?? 0, event);
                    if (event.cancelBubble) break;
                }
                target = target.parentElement;
            }
        };

        const options = { passive: eventType.startsWith('touch') || eventType === 'scroll' };
        root.addEventListener(eventType, listener, options);
        // @ts-ignore
        removers.push(() => root.removeEventListener(eventType, listener, options));
    }

    return () => {
        for (const remove of removers) remove();
    };
}

export type InitOptions = {
    url?: string;
    eventDelegationRoot?: string;
    importObject?: WebAssembly.Imports;
};

const DEFAULT_URL = "/assets/_/main.wasm";

type ActiveRuntime = {
    dispose: () => void;
    options: InitOptions;
};

let activeRuntime: ActiveRuntime | null = null;

function normalizeOptions(options: InitOptions = {}): InitOptions {
    return {
        url: options.url,
        eventDelegationRoot: options.eventDelegationRoot,
        importObject: options.importObject,
    };
}

function registerDevReinit(options: InitOptions): void {
    if (typeof window === 'undefined') return;
    window.__zx_dev_reinit = () => init(options);
}

/** Initialize WASM with the ZX Bridge */
export async function init(options: InitOptions = {}): Promise<{ source: WebAssembly.WebAssemblyInstantiatedSource; bridge: ZxBridge }> {
    const normalizedOptions = normalizeOptions(options);
    if (activeRuntime) {
        activeRuntime.dispose();
        activeRuntime = null;
    }

    const url = options.url ?? (document.getElementById("__$wasmlink") as HTMLLinkElement | null)?.href ?? DEFAULT_URL;
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

    domNodes.clear();

    const disposeDelegation = initEventDelegation(bridge, options.eventDelegationRoot ?? 'body');

    const main = instance.exports.mainClient;
    if (typeof main === 'function') main();

    activeRuntime = {
        options: normalizedOptions,
        dispose: () => {
            disposeDelegation();
            bridge.dispose();
            domNodes.clear();
        },
    };

    // TODO: dev only and prebundle a dev and prod version before publishing
    // if (import.meta.env.DEV)
    registerDevReinit(normalizedOptions);

    return { source, bridge };
}

// Global type declarations
declare global {
    interface HTMLElement {
        __zx_ref?: number;
    }

    interface Window {
        __zx_dev_reinit?: () => Promise<{ source: WebAssembly.WebAssemblyInstantiatedSource; bridge: ZxBridge }>;
    }
}
