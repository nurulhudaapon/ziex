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
    const updatedFromUrl = typeof href === "string" ? await syncLocationFromUrl(href) : false;
    if (!updatedFromUrl) {
        await syncInspectedPageLocation();
    }
    await window.__zx_dev_reinit?.();
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
