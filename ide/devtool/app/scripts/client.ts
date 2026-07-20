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
 * overlay over a component's root element.
 *
 * The devtool derives a CSS `selector` and an `occurrence` index for each
 * component from the serialized tree (see data.zig). The inspected page needs no
 * special markup: we locate the element with
 * `document.querySelectorAll(selector)[occurrence]`. Pass a null/empty selector
 * to hide the overlay.
 */
function inspectedHighlightScript(selector: string | null, occurrence: number): string {
    const selLiteral = JSON.stringify(selector);
    const occLiteral = JSON.stringify(occurrence | 0);
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

        const selector = ${selLiteral};
        const occurrence = ${occLiteral};
        if (!selector) return hideOverlay();

        let nodes;
        try { nodes = document.querySelectorAll(selector); } catch { return hideOverlay(); }
        const el = nodes[occurrence];
        if (!el) return hideOverlay();

        const rect = el.getBoundingClientRect();
        if (!rect || (rect.width <= 0 && rect.height <= 0)) return hideOverlay();

        const overlay = ensureOverlay();
        overlay.style.display = 'block';
        overlay.style.left = rect.left + 'px';
        overlay.style.top = rect.top + 'px';
        overlay.style.width = Math.max(1, rect.width) + 'px';
        overlay.style.height = Math.max(1, rect.height) + 'px';
        state.activeId = selector + '#' + occurrence;
        return true;
    })()`;
}

async function highlightInspectedComponent(selector: string, occurrence: number): Promise<void> {
    await evalInInspectedWindow(inspectedHighlightScript(selector, occurrence));
}

async function clearInspectedComponentHighlight(): Promise<void> {
    await evalInInspectedWindow(inspectedHighlightScript(null, 0));
}

/**
 * Build a script that, when eval'd in the inspected page, scrolls a component's
 * root element into view (only when it isn't already fully visible) and pins the
 * highlight overlay onto it while the smooth scroll settles.
 *
 * Reuses the same locator scheme and overlay as {@link inspectedHighlightScript}
 * so clicking a component in the tree focuses the exact element the hover
 * highlight points at.
 */
function inspectedFocusScript(selector: string, occurrence: number): string {
    const selLiteral = JSON.stringify(selector);
    const occLiteral = JSON.stringify(occurrence | 0);
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

        const selector = ${selLiteral};
        const occurrence = ${occLiteral};
        if (!selector) return false;

        let nodes;
        try { nodes = document.querySelectorAll(selector); } catch { return false; }
        const el = nodes[occurrence];
        if (!el) return false;

        const overlay = ensureOverlay();
        const place = () => {
            const rect = el.getBoundingClientRect();
            if (!rect || (rect.width <= 0 && rect.height <= 0)) {
                overlay.style.display = 'none';
                return;
            }
            overlay.style.display = 'block';
            overlay.style.left = rect.left + 'px';
            overlay.style.top = rect.top + 'px';
            overlay.style.width = Math.max(1, rect.width) + 'px';
            overlay.style.height = Math.max(1, rect.height) + 'px';
        };

        const rect = el.getBoundingClientRect();
        const vh = window.innerHeight || document.documentElement.clientHeight;
        const vw = window.innerWidth || document.documentElement.clientWidth;
        const fullyVisible = rect.top >= 0 && rect.left >= 0 && rect.bottom <= vh && rect.right <= vw;

        place();
        state.activeId = selector + '#' + occurrence;

        if (!fullyVisible) {
            el.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' });
            // Keep the overlay pinned to the element while the smooth scroll runs.
            const start = Date.now();
            const timer = setInterval(() => {
                place();
                if (Date.now() - start > 600) clearInterval(timer);
            }, 16);
        }
        return true;
    })()`;
}

async function focusInspectedComponent(selector: string, occurrence: number): Promise<void> {
    if (!selector) return;
    await evalInInspectedWindow(inspectedFocusScript(selector, occurrence));
}

let hoveredKey: string | null = null;

function getHoveredComponentButton(target: EventTarget | null): HTMLElement | null {
    if (!(target instanceof Element)) return null;
    return target.closest('.component-select-btn, .component-select-btn-leaf');
}

async function startHover(selector: string, occurrence: number): Promise<void> {
    if (!selector) return;
    const key = selector + '#' + occurrence;
    if (hoveredKey === key) return;
    hoveredKey = key;
    await highlightInspectedComponent(selector, occurrence);
}

async function stopHover(): Promise<void> {
    if (!hoveredKey) return;
    hoveredKey = null;
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
    const selector = btn.getAttribute('data-sel');
    if (!selector) return;
    const occurrence = parseInt(btn.getAttribute('data-idx') || '0', 10) || 0;
    await startHover(selector, occurrence);
});

document.addEventListener('mouseout', async (e: MouseEvent) => {
    const from = getHoveredComponentButton(e.target);
    if (!from) return;
    const to = getHoveredComponentButton(e.relatedTarget);
    if (to) return;
    await stopHover();
});

// Clicking a component in the tree focuses it in the inspected page, scrolling
// it into view when it isn't already visible. The framework's own onclick
// handler (handleComponentClick) still runs to update the selected component.
document.addEventListener('click', async (e: MouseEvent) => {
    const btn = getHoveredComponentButton(e.target);
    if (!btn) return;
    const selector = btn.getAttribute('data-sel');
    if (!selector) return;
    const occurrence = parseInt(btn.getAttribute('data-idx') || '0', 10) || 0;
    await focusInspectedComponent(selector, occurrence);
});

window.addEventListener('blur', async () => {
    await stopHover();
});
