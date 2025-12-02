import { ZigJS } from "jsz/js/src";

const DEFAULT_URL = "/assets/main.wasm";
const MAX_EVENTS = 100;

const jsz = new ZigJS();
const importObject = {
    module: {},
    env: {},
    ...jsz.importObject(),
};

class ZXInstance {

    exports: WebAssembly.Exports;
    events: Event[];
    actions: Record<string, (eventId: number) => void>;

    constructor({ exports, events = [] }: ZXInstanceOptions) {
        this.exports = exports;
        this.events = events;
        this.actions = {};

        Object.entries(exports).forEach(([name, func]) => {
            if (typeof func !== 'function') return;

            this.actions[name] = this.#actionWrapper.bind(this, name);
        });
    }

    addEvent(event: Event) {
        if (this.events.length >= MAX_EVENTS) 
            this.events.length = 0;

        const idx = this.events.push(event);
        
        return idx - 1;
    }
    
    #actionWrapper(name: string, ...args: any[]) {
        const func = this.exports[name];
        if (typeof func !== 'function') throw new Error(`Action ${name} is not a function`);

        const eventId = this.addEvent(args[0]);
        return func(eventId);
    }
}

export async function init(options: InitOptions = {}) {
    const url = options?.url ?? DEFAULT_URL;
    const { instance } = await WebAssembly.instantiateStreaming(fetch(url), importObject);

    jsz.memory = instance.exports.memory as WebAssembly.Memory;
    window._zx = new ZXInstance({ exports: instance.exports  });

    const main = instance.exports.mainClient;
    if (typeof main === 'function') main();

}

export type InitOptions = {
    url?: string;
};

type ZXInstanceOptions = {
    exports: ZXInstance['exports'];
    events?: ZXInstance['events']
}

declare global {
    interface Window {
        _zx: ZXInstance;
    }
}