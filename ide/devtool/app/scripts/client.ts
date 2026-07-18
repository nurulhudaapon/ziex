import { createBrowserKVBindings } from "../../../../pkg/ziex/src/browser/kv";
import { init } from "../../../../pkg/ziex/src/wasm";

const HOST_STORAGE_KEY = "zx-devtool-host-v2";
const PATH_STORAGE_KEY = "zx-devtool-path-v1";

const kvBindings = createBrowserKVBindings();
const defaultKV = kvBindings.default;

async function persistLocation(origin: string, pathname: string): Promise<boolean> {
    if (!defaultKV || !origin) return false;
    try {
        await Promise.all([
            defaultKV.put(HOST_STORAGE_KEY, origin),
            defaultKV.put(PATH_STORAGE_KEY, pathname || "/"),
        ]);
        return true;
    } catch {
        return false;
    }
}

async function syncInspectedPageLocation(): Promise<boolean> {
    const chromeApi = (globalThis as any).chrome;
    if (!defaultKV || !chromeApi?.devtools?.inspectedWindow?.eval) return false;

    return await new Promise<boolean>((resolve) => {
        chromeApi.devtools.inspectedWindow.eval(
            `(() => {
                const hook = window.__ZIEX_DEVTOOLS_GLOBAL_HOOK__;
                return hook ? hook.location : null;
            })()`,
            async (
                location: { origin?: unknown; pathname?: unknown } | null,
                exceptionInfo: { isException?: boolean } | undefined
            ) => {
                if (exceptionInfo?.isException || !location) {
                    resolve(false);
                    return;
                }

                try {
                    const origin = typeof location.origin === "string" ? location.origin : "";
                    const pathname = typeof location.pathname === "string" ? location.pathname : "/";
                    resolve(await persistLocation(origin, pathname));
                } catch {
                    resolve(false);
                }
            }
        );
    });
}

async function syncLocationFromUrl(href: string): Promise<boolean> {
    try {
        const url = new URL(href);
        return await persistLocation(url.origin, url.pathname || "/");
    } catch {
        return false;
    }
}

async function refreshFromNavigation(href?: string): Promise<void> {
    await clearInspectedComponentHighlight();
    const updatedFromUrl = typeof href === "string" ? await syncLocationFromUrl(href) : false;
    if (!updatedFromUrl) {
        await syncInspectedPageLocation();
    }
    await window.__zx_dev_reinit?.();
}

function evalInInspectedWindow<T = unknown>(expression: string): Promise<T | undefined> {
    const chromeApi = (globalThis as any).chrome;
    if (!chromeApi?.devtools?.inspectedWindow?.eval) return Promise.resolve(undefined);

    return new Promise<T | undefined>((resolve) => {
        chromeApi.devtools.inspectedWindow.eval(
            expression,
            (result: T | undefined, exceptionInfo: { isException?: boolean } | undefined) => {
                if (exceptionInfo?.isException) {
                    resolve(undefined);
                    return;
                }
                resolve(result);
            }
        );
    });
}

/**
 * Build a script that, when eval'd in the inspected page, positions a highlight
 * overlay over the *union* of every element owned by the component `componentId`.
 *
 * In dev builds the ziex renderers stamp each element with a `data-zx-owner`
 * attribute carrying its owning component's id, so a single `querySelectorAll`
 * finds the component's whole rendered output (native elements included). Pass
 * `null` to hide the overlay.
 */
function inspectedHighlightScript(componentId: string | null): string {
    const idLiteral = JSON.stringify(componentId);
    return `(() => {
        const key = '__ZX_DEVTOOL_HOVER_OVERLAY__';
        const root = window;
        const state = root[key] || (root[key] = { overlay: null, activeId: null });

        const ensureOverlay = () => {
            if (state.overlay && state.overlay.isConnected) return state.overlay;
            const overlay = document.createElement('div');
            overlay.style.position = 'fixed';
            overlay.style.zIndex = '2147483647';
            overlay.style.pointerEvents = 'none';
            overlay.style.border = '2px solid #41b883';
            overlay.style.background = 'rgba(65, 184, 131, 0.18)';
            overlay.style.borderRadius = '4px';
            overlay.style.boxSizing = 'border-box';
            overlay.style.display = 'none';
            document.documentElement.appendChild(overlay);
            state.overlay = overlay;
            return overlay;
        };

        const hideOverlay = () => {
            if (state.overlay) state.overlay.style.display = 'none';
            state.activeId = null;
            return false;
        };

        const componentId = ${idLiteral};
        if (!componentId) return hideOverlay();

        /* Component ids are "c<hex>" or "c<hex>_<n>", so no escaping is needed. */
        const nodes = document.querySelectorAll('[data-zx-owner="' + componentId + '"]');
        if (!nodes.length) return hideOverlay();

        /* Union the bounding box of every element the component owns. */
        let minLeft = Infinity, minTop = Infinity, maxRight = -Infinity, maxBottom = -Infinity;
        nodes.forEach((el) => {
            const rect = el.getBoundingClientRect();
            if (!rect || (rect.width <= 0 && rect.height <= 0)) return;
            if (rect.left   < minLeft)   minLeft   = rect.left;
            if (rect.top    < minTop)    minTop    = rect.top;
            if (rect.right  > maxRight)  maxRight  = rect.right;
            if (rect.bottom > maxBottom) maxBottom = rect.bottom;
        });

        if (minLeft === Infinity) return hideOverlay();
        const width  = maxRight - minLeft;
        const height = maxBottom - minTop;
        if (width <= 0 && height <= 0) return hideOverlay();

        const overlay = ensureOverlay();
        overlay.style.display = 'block';
        overlay.style.left = minLeft + 'px';
        overlay.style.top = minTop + 'px';
        overlay.style.width = Math.max(1, width) + 'px';
        overlay.style.height = Math.max(1, height) + 'px';
        state.activeId = componentId;
        return true;
    })()`;
}

async function highlightInspectedComponent(componentId: string): Promise<void> {
    await evalInInspectedWindow(inspectedHighlightScript(componentId));
}

async function clearInspectedComponentHighlight(): Promise<void> {
    await evalInInspectedWindow(inspectedHighlightScript(null));
}

let hoveredComponentId: string | null = null;

function getHoveredComponentButton(target: EventTarget | null): HTMLElement | null {
    if (!(target instanceof Element)) return null;
    return target.closest('.component-select-btn, .component-select-btn-leaf');
}

async function startHover(componentId: string): Promise<void> {
    if (!componentId || hoveredComponentId === componentId) return;
    hoveredComponentId = componentId;
    await highlightInspectedComponent(componentId);
}

async function stopHover(): Promise<void> {
    if (!hoveredComponentId) return;
    hoveredComponentId = null;
    await clearInspectedComponentHighlight();
}

async function main() {
    await syncInspectedPageLocation();
    await init({ kv: kvBindings });
}
main();
const chromeApi = (globalThis as any).chrome;
if (chromeApi?.devtools?.network?.onNavigated) {
    chromeApi.devtools.network.onNavigated.addListener(async (href: string) => {
        await refreshFromNavigation(href);
    });
}

// Intercept clicks on route links and navigate the inspected page instead of
// opening a new tab, when running inside the Chrome DevTools extension.
document.addEventListener('click', (e: MouseEvent) => {
    const anchor = (e.target as Element)?.closest?.('[data-route-navigate]') as HTMLElement | null;
    if (!anchor) return;

    const chromeApi = (globalThis as any).chrome;
    if (!chromeApi?.devtools?.inspectedWindow?.eval) return;

    e.preventDefault();
    const path = anchor.getAttribute('data-route-navigate') || '/';
    chromeApi.devtools.inspectedWindow.eval(
        `window.location.pathname = ${JSON.stringify(path)}`
    );
});

// Listen for SPA navigation events forwarded from the content script
// via devtools-background.js.
window.addEventListener('zx-navigation', async (e: Event) => {
    const href = (e as CustomEvent).detail?.href;
    if (typeof href === 'string') {
        await refreshFromNavigation(href);
    }
});

document.addEventListener('mouseover', async (e: MouseEvent) => {
    const btn = getHoveredComponentButton(e.target);
    if (!btn) return;
    const componentId = btn.getAttribute('data-owner-id');
    if (!componentId) return;
    await startHover(componentId);
});

document.addEventListener('mouseout', async (e: MouseEvent) => {
    const from = getHoveredComponentButton(e.target);
    if (!from) return;
    const to = getHoveredComponentButton(e.relatedTarget);
    if (to) return;
    await stopHover();
});

window.addEventListener('blur', async () => {
    await stopHover();
});
