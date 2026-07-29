import { RangeSetBuilder } from "@codemirror/state";
import {
    EditorView,
    ViewPlugin,
    Decoration,
    hoverTooltip,
    type DecorationSet,
    type ViewUpdate,
    type PluginValue,
} from "@codemirror/view";
import { foldService } from "@codemirror/language";
import { setDiagnostics } from "@codemirror/lint";
import {
    LSPClient,
    LSPPlugin,
    serverCompletion,
    type LSPClientExtension,
    type Transport,
} from "@codemirror/lsp-client";
import { htmlLanguage } from "@codemirror/lang-html";
import { cssLanguage } from "@codemirror/lang-css";
import { javascriptLanguage, jsxLanguage, tsxLanguage } from "@codemirror/lang-javascript";
import type * as LSP from "vscode-languageserver-protocol";

const HOVER_KIND_ONLY = /^\([A-Za-z]+\)$/;
const ZX_IMPORT_RESOLVED = /@import\("(?:\.\.\/)*zx\/src\/root\.zig"\)/g;

type PlaygroundLspUiHooks = {
    openLocalFile?: (path: string) => void;
};

let playgroundLspUiHooks: PlaygroundLspUiHooks = {};

export function setPlaygroundLspUiHooks(hooks: PlaygroundLspUiHooks) {
    playgroundLspUiHooks = hooks;
}

function isHoverKindLabel(text: string): boolean {
    return HOVER_KIND_ONLY.test(text.trim());
}

/** ZLS sees rewritten `@import("…/zx/src/root.zig")`; show the user-facing `@import("zx")`. */
function displayZxImport(value: string): string {
    return value.replace(ZX_IMPORT_RESOLVED, '@import("zx")');
}

function stripHoverKindLabels(value: string): string {
    return displayZxImport(value)
        // Remove kind-only fenced blocks first (otherwise stripping the label leaves an empty <pre>).
        .replace(/```[^\n]*\r?\n\s*\([A-Za-z]+\)\s*\r?\n```/g, "")
        .replace(/(^|\n)\s*\([A-Za-z]+\)\s*(?=\n|$)/g, "\n")
        .replace(/```[^\n]*\r?\n\s*\r?\n```/g, "")
        .replace(/\n{2,}/g, "\n")
        .trim();
}

function filterHoverContents(contents: LSP.Hover["contents"]): LSP.Hover["contents"] | null {
    if (typeof contents === "string") {
        const trimmed = stripHoverKindLabels(contents);
        return trimmed && !isHoverKindLabel(trimmed) ? trimmed : null;
    }
    if (Array.isArray(contents)) {
        const filtered: LSP.MarkedString[] = [];
        for (const item of contents as unknown as LSP.MarkedString[]) {
            if (typeof item === "string") {
                const trimmed = stripHoverKindLabels(item);
                if (trimmed && !isHoverKindLabel(trimmed)) filtered.push(trimmed);
                continue;
            }
            if (item && typeof item === "object" && "value" in item) {
                const raw = String((item as any).value);
                if (isHoverKindLabel(raw)) continue;
                const trimmed = stripHoverKindLabels(raw);
                if (!trimmed || isHoverKindLabel(trimmed)) continue;
                filtered.push({ ...(item as any), value: trimmed });
                continue;
            }
            filtered.push(item);
        }
        return filtered.length > 0 ? filtered : null;
    }
    if (contents && typeof contents === "object" && "value" in contents) {
        if (isHoverKindLabel(contents.value)) return null;
        const trimmed = stripHoverKindLabels(contents.value);
        if (!trimmed || isHoverKindLabel(trimmed)) return null;
        return { ...contents, value: trimmed };
    }
    return contents;
}

function renderHoverItem(plugin: LSPPlugin, item: string | LSP.MarkedString | LSP.MarkupContent): string {
    if (typeof item === "string") {
        if (isHoverKindLabel(item)) return "";
        return plugin.docToHTML(item, "markdown");
    }
    if ("language" in item && item.language) {
        if (isHoverKindLabel(item.value)) return "";
        return plugin.docToHTML(`\`\`\`${item.language}\n${item.value.trimEnd()}\n\`\`\``, "markdown");
    }
    if ("kind" in item) {
        if (isHoverKindLabel(item.value)) return "";
        return plugin.docToHTML(item);
    }
    if (isHoverKindLabel(item.value)) return "";
    return plugin.docToHTML(item.value, "markdown");
}

function cleanupHoverHtml(html: string): string {
    return html
        .replace(/<pre\b[^>]*>\s*(?:<code\b[^>]*>\s*<\/code>\s*)?<\/pre>/gi, "")
        .replace(/<pre\b[^>]*>\s*<code\b[^>]*>\s*\([A-Za-z]+\)\s*<\/code>\s*<\/pre>/gi, "")
        .replace(/(?:<br\s*\/?>\s*)+$/gi, "")
        .replace(/(?:<p>(?:\s|&nbsp;|<br\s*\/?>)*<\/p>\s*)+$/gi, "")
        .trim();
}

function renderHoverHtml(plugin: LSPPlugin, contents: LSP.Hover["contents"]): string {
    if (Array.isArray(contents)) {
        return cleanupHoverHtml(
            contents.map((item) => renderHoverItem(plugin, item)).filter(Boolean).join(""),
        );
    }
    return cleanupHoverHtml(renderHoverItem(plugin, contents));
}

function normalizeLocalHoverPath(href: string): string | null {
    if (!href) return null;
    if (href.startsWith("file://")) {
        try {
            const url = new URL(href);
            return decodeURIComponent(url.pathname).replace(/^\/+/, "");
        } catch {
            return href.replace(/^file:\/+/, "").replace(/^\/+/, "").split("#")[0] ?? null;
        }
    }
    if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(href)) return null;
    if (href.startsWith("#")) return null;
    if (/\.(?:zig|zx|zon|mdzx|html|css|js|jsx|ts|tsx|md)$/.test(href)) {
        return href.replace(/^\/+/, "").split("#")[0] ?? null;
    }
    return null;
}

function decorateHoverLinks(root: HTMLElement) {
    for (const anchor of root.querySelectorAll("a[href]")) {
        const href = anchor.getAttribute("href") ?? "";
        const localPath = normalizeLocalHoverPath(href);
        if (localPath) {
            anchor.setAttribute("data-local-path", localPath);
            anchor.addEventListener(
                "click",
                (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    playgroundLspUiHooks.openLocalFile?.(localPath);
                },
                true,
            );
            continue;
        }
        anchor.setAttribute("target", "_blank");
        anchor.setAttribute("rel", "noopener noreferrer");
    }
}

function playgroundHoverTooltips() {
    return hoverTooltip((view, pos) => {
        const plugin = LSPPlugin.get(view);
        if (!plugin || plugin.client.serverCapabilities?.hoverProvider == null) {
            return null;
        }
        plugin.client.sync();
        return plugin.client
            .request("textDocument/hover", {
                position: plugin.toPosition(pos),
                textDocument: { uri: plugin.uri },
            })
            .then((result) => {
                const hover = result as LSP.Hover | null;
                if (!hover?.contents) return null;
                const contents = filterHoverContents(hover.contents);
                if (!contents) return null;
                const html = renderHoverHtml(plugin, contents);
                if (!html.trim()) return null;
                return {
                    pos: hover.range ? plugin.fromPosition(hover.range.start) : pos,
                    end: hover.range ? plugin.fromPosition(hover.range.end) : pos,
                    create() {
                        const elt = document.createElement("div");
                        elt.className = "cm-lsp-hover-tooltip cm-lsp-documentation";
                        elt.innerHTML = html;
                        decorateHoverLinks(elt);
                        return { dom: elt };
                    },
                    above: true,
                };
            });
    }, {
        hoverTime: 60,
        hideOn: (tr) => tr.docChanged,
    });
}

function workspaceConfiguration(): LSPClientExtension {
    return {
        clientCapabilities: { workspace: { configuration: true } },
    };
}

function interceptConfiguration(transport: Transport): Transport {
    const wrappers = new Map<(value: string) => void, (value: string) => void>();
    return {
        send: (message) => transport.send(message),
        subscribe(handler) {
            const wrapped = (raw: string) => {
                let msg: any;
                try {
                    msg = JSON.parse(raw);
                } catch {
                    return handler(raw);
                }
                if (msg.method === "workspace/configuration" && msg.id !== undefined) {
                    const items: LSP.ConfigurationItem[] = msg.params?.items ?? [];
                    const result = items.map((item) =>
                        item.section === "zls.prefer_ast_check_as_child_process" ? false : null,
                    );
                    transport.send(JSON.stringify({ jsonrpc: "2.0", id: msg.id, result }));
                    return;
                }
                return handler(raw);
            };
            wrappers.set(handler, wrapped);
            transport.subscribe(wrapped);
        },
        unsubscribe(handler) {
            const wrapped = wrappers.get(handler);
            if (wrapped) {
                transport.unsubscribe(wrapped);
                wrappers.delete(handler);
            }
        },
    };
}

function zlsDiagnostics(): LSPClientExtension {
    const autoSync = ViewPlugin.fromClass(
        class {
            pending = -1;
            update(update: ViewUpdate) {
                if (!update.docChanged) return;
                if (this.pending > -1) clearTimeout(this.pending);
                this.pending = window.setTimeout(() => {
                    this.pending = -1;
                    LSPPlugin.get(update.view)?.client.sync();
                }, 500);
            }
            destroy() {
                if (this.pending > -1) clearTimeout(this.pending);
            }
        },
    );

    /** Per-URI diagnostics keyed by LSP `source` so ZX + ZLS can coexist. */
    const byUri = new Map<string, Map<string, LSP.Diagnostic[]>>();

    return {
        clientCapabilities: { textDocument: { publishDiagnostics: {} } },
        notificationHandlers: {
            "textDocument/publishDiagnostics": (client, params: LSP.PublishDiagnosticsParams) => {
                const file = client.workspace.getFile(params.uri);
                if (!file) return false;
                const view = file.getView();
                const plugin = view && LSPPlugin.get(view);
                if (!view || !plugin) return false;

                let sources = byUri.get(params.uri);
                if (!sources) {
                    sources = new Map();
                    byUri.set(params.uri, sources);
                }

                const serverSource =
                    (params as LSP.PublishDiagnosticsParams & { ziexSource?: string }).ziexSource;

                // Group this publish by diagnostic source (default from worker tag / "zls").
                const grouped = new Map<string, LSP.Diagnostic[]>();
                for (const d of params.diagnostics) {
                    const key = d.source ?? serverSource ?? "zls";
                    const list = grouped.get(key) ?? [];
                    list.push(d);
                    grouped.set(key, list);
                }
                // Empty publish clears only that server's contribution.
                if (params.diagnostics.length === 0) {
                    if (serverSource) sources.delete(serverSource);
                    else sources.clear();
                } else {
                    for (const [key, list] of grouped) sources.set(key, list);
                }

                const merged = [...sources.values()].flat();
                const diagnostics = merged
                    .filter((d) => d.message !== "expected expression, found '<'")
                    .map((item) => ({
                        from: plugin.unsyncedChanges.mapPos(plugin.fromPosition(item.range.start, plugin.syncedDoc)),
                        to: plugin.unsyncedChanges.mapPos(plugin.fromPosition(item.range.end, plugin.syncedDoc)),
                        severity: ({ 1: "error", 2: "warning", 3: "info", 4: "info" } as const)[item.severity ?? 1],
                        message:
                            item.source
                                ? `[${item.source}] ${typeof item.message === "string" ? item.message : item.message.value}`
                                : typeof item.message === "string"
                                  ? item.message
                                  : item.message.value,
                    }))
                    .sort((a, b) => a.from - b.from);

                view.dispatch(setDiagnostics(view.state, diagnostics));
                return true;
            },
        },
        editorExtension: autoSync,
    };
}

function zlsLogging(): LSPClientExtension {
    return {
        notificationHandlers: {
            "window/logMessage": (_client, params: LSP.LogMessageParams) => {
                const fns = [undefined, console.error, console.warn, console.info, console.log, console.debug];
                (fns[params.type] ?? console.log)("LSP --- ", params.message);
                return true;
            },
        },
    };
}

const semanticTokens = ViewPlugin.fromClass(
    class {
        decorations: DecorationSet = Decoration.none;

        constructor(view: EditorView) {
            void this.requestTokens(view);
        }

        update(update: ViewUpdate) {
            if (update.docChanged) void this.requestTokens(update.view);
        }

        async requestTokens(view: EditorView) {
            const plugin = LSPPlugin.get(view);
            if (!plugin) return;
            const { client, uri } = plugin;
            if (client.serverCapabilities && !client.serverCapabilities.semanticTokensProvider) return;

            client.sync();
            const tokens = await client.request<LSP.SemanticTokensParams, LSP.SemanticTokens | null>(
                "textDocument/semanticTokens/full",
                { textDocument: { uri } },
            );
            if (!tokens) return;

            const provider = client.serverCapabilities?.semanticTokensProvider;
            if (!provider || !("legend" in provider)) return;
            const { tokenTypes, tokenModifiers } = provider.legend;

            const map = plugin.unsyncedChanges;
            const syncedDoc = plugin.syncedDoc;
            const builder = new RangeSetBuilder<Decoration>();

            let line = 0;
            let col = 0;
            const data = tokens.data;
            for (let i = 0; i < data.length; i += 5) {
                const deltaLine = data[i];
                const deltaStartChar = data[i + 1];
                const length = data[i + 2];
                const tokenType = data[i + 3];
                const tokenModifierBitSet = data[i + 4];

                line += deltaLine;
                col = deltaLine === 0 ? col + deltaStartChar : deltaStartChar;

                if (line + 1 > syncedDoc.lines) continue;

                let className = `st-${tokenTypes[tokenType]}`;
                let bits = tokenModifierBitSet;
                let index = 0;
                while (bits !== 0) {
                    if (bits & 1) className += ` sm-${tokenModifiers[index]}`;
                    bits >>= 1;
                    index += 1;
                }

                const lineStart = syncedDoc.line(line + 1).from;
                const lineEnd = syncedDoc.line(line + 1).to;
                const fromRaw = Math.min(lineStart + col, lineEnd);
                const toRaw = Math.min(lineStart + col + length, lineEnd);
                if (toRaw <= fromRaw) continue;

                let from: number;
                let to: number;
                try {
                    from = map.mapPos(fromRaw);
                    to = map.mapPos(toRaw);
                } catch {
                    continue;
                }
                if (to > from) builder.add(from, to, Decoration.mark({ class: className }));
            }

            this.decorations = builder.finish();
            view.dispatch({});
        }
    },
    { decorations: (v) => v.decorations },
);

class FoldRangePlugin implements PluginValue {
    ranges = new Map<number, LSP.FoldingRange>();

    constructor(view: EditorView) {
        void this.requestRanges(view);
    }

    update(update: ViewUpdate) {
        if (update.docChanged) {
            this.ranges.clear();
            void this.requestRanges(update.view);
        }
    }

    async requestRanges(view: EditorView) {
        const plugin = LSPPlugin.get(view);
        if (!plugin) return;
        const { client, uri } = plugin;
        if (client.serverCapabilities && !client.serverCapabilities.foldingRangeProvider) return;

        client.sync();
        const ranges = await client.request<LSP.FoldingRangeParams, LSP.FoldingRange[] | null>(
            "textDocument/foldingRange",
            { textDocument: { uri } },
        );

        this.ranges.clear();
        if (ranges) for (const range of ranges) this.ranges.set(range.startLine, range);
    }
}

const foldRanges = ViewPlugin.fromClass(FoldRangePlugin);

const lspFolding = foldService.of((state, lineStart) => {
    const view = foldingView;
    if (!view) return null;
    const fold = view.plugin(foldRanges);
    if (!fold) return null;

    const startLine = state.doc.lineAt(lineStart);
    const range = fold.ranges.get(startLine.number - 1);
    if (!range || range.endLine + 1 > state.doc.lines) return null;

    const endLine = state.doc.line(range.endLine + 1);
    return {
        from: range.startCharacter != undefined ? lineStart + range.startCharacter : startLine.to,
        to: range.endCharacter != undefined ? endLine.from + range.endCharacter : endLine.to,
    };
});

let foldingView: EditorView | null = null;
const trackFoldingView = EditorView.updateListener.of((u) => {
    foldingView = u.view;
});

export function workerTransport(worker: Worker): Transport {
    const handlers = new Set<(value: string) => void>();
    worker.addEventListener("message", (ev: MessageEvent) => {
        const raw: string = ev.data;
        try {
            if (typeof raw === "string" && JSON.parse(raw)?.stderr !== undefined) return;
        } catch {
            return;
        }
        for (const h of handlers) h(raw);
    });
    return {
        send: (message) => worker.postMessage(message),
        subscribe: (handler) => handlers.add(handler),
        unsubscribe: (handler) => handlers.delete(handler),
    };
}

export function createZlsClient(transport: Transport): LSPClient {
    const client = new LSPClient({
        rootUri: "file:///",
        highlightLanguage: (name) => {
            switch (name.toLowerCase()) {
                case "html":
                case "xml":
                    return htmlLanguage;
                case "css":
                    return cssLanguage;
                case "javascript":
                case "js":
                    return javascriptLanguage;
                case "jsx":
                    return jsxLanguage;
                case "typescript":
                case "ts":
                    return tsxLanguage;
                case "tsx":
                    return tsxLanguage;
                default:
                    return null;
            }
        },
        extensions: [
            workspaceConfiguration(),
            zlsDiagnostics(),
            zlsLogging(),
            serverCompletion(),
            playgroundHoverTooltips(),
            semanticTokens,
            foldRanges,
            lspFolding,
            trackFoldingView,
        ],
    });

    client.connect(interceptConfiguration(transport));
    return client;
}

export type { Transport };
