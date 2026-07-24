import { RangeSetBuilder } from "@codemirror/state";
import {
    EditorView,
    ViewPlugin,
    Decoration,
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
    hoverTooltips,
    type LSPClientExtension,
    type Transport,
} from "@codemirror/lsp-client";
import type * as LSP from "vscode-languageserver-protocol";

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

    return {
        clientCapabilities: { textDocument: { publishDiagnostics: {} } },
        notificationHandlers: {
            "textDocument/publishDiagnostics": (client, params: LSP.PublishDiagnosticsParams) => {
                const file = client.workspace.getFile(params.uri);
                if (!file) return false;
                const view = file.getView();
                const plugin = view && LSPPlugin.get(view);
                if (!view || !plugin) return false;

                const diagnostics = params.diagnostics
                    .filter((d) => d.message !== "expected expression, found '<'")
                    .map((item) => ({
                        from: plugin.unsyncedChanges.mapPos(plugin.fromPosition(item.range.start, plugin.syncedDoc)),
                        to: plugin.unsyncedChanges.mapPos(plugin.fromPosition(item.range.end, plugin.syncedDoc)),
                        severity: ({ 1: "error", 2: "warning", 3: "info", 4: "info" } as const)[item.severity ?? 1],
                        message: item.message,
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
                (fns[params.type] ?? console.log)("ZLS --- ", params.message);
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
        extensions: [
            workspaceConfiguration(),
            zlsDiagnostics(),
            zlsLogging(),
            serverCompletion(),
            hoverTooltips(),
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
