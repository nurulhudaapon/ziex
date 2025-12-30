import { ZigJS } from "jsz/js/src";

const DEFAULT_URL = "/assets/main.wasm";
const MAX_EVENTS = 100;

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

// Map event type names to enum values (must match Client.zig EventType)
const EVENT_TYPE_MAP: Record<DelegatedEvent, number> = {
    'click': 0,
    'dblclick': 1,
    'input': 2,
    'change': 3,
    'submit': 4,
    'focus': 5,
    'blur': 6,
    'keydown': 7,
    'keyup': 8,
    'keypress': 9,
    'mouseenter': 10,
    'mouseleave': 11,
    'mousedown': 12,
    'mouseup': 13,
    'mousemove': 14,
    'touchstart': 15,
    'touchend': 16,
    'touchmove': 17,
    'scroll': 18,
};

const jsz = new ZigJS();
const importObject = {
    module: {},
    env: {},
    ...jsz.importObject(),
};

class ZXInstance {

    exports: WebAssembly.Exports;
    events: Event[];
    #eventDelegationInitialized: boolean = false;

    constructor({ exports, events = [] }: ZXInstanceOptions) {
        this.exports = exports;
        this.events = events;
    }

    addEvent(event: Event) {
        if (this.events.length >= MAX_EVENTS)
            this.events.length = 0;

        const idx = this.events.push(event);

        return idx - 1;
    }

    /**
     * Initialize event delegation on a root element
     * This attaches a single event listener for each event type at the root,
     * and uses __zx_ref to look up the corresponding VElement in WASM
     */
    initEventDelegation(rootSelector: string = 'body') {
        if (this.#eventDelegationInitialized) return;

        const root = document.querySelector(rootSelector);
        if (!root) {
            console.warn(`[ZX] Event delegation root "${rootSelector}" not found`);
            return;
        }

        // Attach delegated event listeners
        for (const eventType of DELEGATED_EVENTS) {
            root.addEventListener(eventType, (event: Event) => {
                this.#handleDelegatedEvent(eventType, event);
            }, { passive: eventType.startsWith('touch') || eventType === 'scroll' });
        }

        this.#eventDelegationInitialized = true;
        console.debug('[ZX] Event delegation initialized on', rootSelector);
    }

    /**
     * Handle a delegated event by walking up from the target to find __zx_ref
     */
    #handleDelegatedEvent(eventType: DelegatedEvent, event: Event) {
        let target = event.target as HTMLElement | null;

        // Walk up the DOM tree to find an element with __zx_ref
        while (target && target !== document.body) {
            const zxRef = target.__zx_ref;

            if (zxRef !== undefined) {
                const eventId = this.addEvent(event);
                const handleEvent = this.exports.handleEvent as EventHandler | undefined;
                if (typeof handleEvent === 'function') {
                    const eventTypeId = EVENT_TYPE_MAP[eventType] ?? 0;
                    handleEvent(BigInt(zxRef), eventTypeId, BigInt(eventId));
                }

                break;
            }

            target = target.parentElement;
        }
    }

    /** Get the VElement ID from a DOM element */
    getZxRef(element: HTMLElement): number | undefined {
        return element.__zx_ref;
    }
}

export async function init(options: InitOptions = {}) {
    const url = options?.url ?? DEFAULT_URL;
    const { instance } = await WebAssembly.instantiateStreaming(fetch(url), importObject);

    jsz.memory = instance.exports.memory as WebAssembly.Memory;
    window._zx = new ZXInstance({ exports: instance.exports });

    // Initialize event delegation
    window._zx.initEventDelegation(options.eventDelegationRoot ?? 'body');

    const main = instance.exports.mainClient;
    if (typeof main === 'function') main();

}

export type InitOptions = {
    /** URL to the WASM file (default: /assets/main.wasm) */
    url?: string;
    /** CSS selector for the event delegation root element (default: 'body') */
    eventDelegationRoot?: string;
};

type ZXInstanceOptions = {
    exports: ZXInstance['exports'];
    events?: ZXInstance['events']
}

type DelegatedEvent = typeof DELEGATED_EVENTS[number];
type EventHandler = (zxRef: bigint, eventTypeId: number, eventId: bigint) => void;

declare global {
    interface Window {
        _zx: ZXInstance;
    }
    interface HTMLElement {
        /**
         * The VElement ID of the element
         */
        __zx_ref?: number;
    }
}