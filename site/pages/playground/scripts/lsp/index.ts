import { autocompletion } from "@codemirror/autocomplete";
import { setDiagnostics } from "@codemirror/lint";
import { ChangeSpec, Facet, Prec, RangeSetBuilder, StateEffect, StateField } from "@codemirror/state";
import { EditorView, ViewPlugin, Tooltip, hoverTooltip, keymap, DecorationSet, Decoration } from '@codemirror/view';
import {
    DiagnosticSeverity,
    CompletionItemKind,
    CompletionTriggerKind,
} from "vscode-languageserver-protocol";

import type {
    Completion,
    CompletionContext,
    CompletionResult,
} from '@codemirror/autocomplete';
import type { PublishDiagnosticsParams } from 'vscode-languageserver-protocol';
import type { ViewUpdate, PluginValue } from '@codemirror/view';
import { Text } from '@codemirror/state';
import type * as LSP from 'vscode-languageserver-protocol';
import { SemanticTokenTypes } from 'vscode-languageserver-protocol';
import { foldService } from "@codemirror/language";

const CompletionItemKindMap = Object.fromEntries(
    Object.entries(CompletionItemKind).map(([key, value]) => [value, key])
) as Record<CompletionItemKind, string>;

const useLast = (values: readonly any[]) => values.reduce((_, v) => v, '');

const client = Facet.define<LspClient, LspClient>({ combine: useLast });
const documentUri = Facet.define<string, string>({ combine: useLast });
const languageId = Facet.define<string, string>({ combine: useLast });

export type JsonRpcId = string | number;
type OutboundRequest = {
    promise: Promise<any>;
    resolve: Function;
    reject: Function;
};

export type JsonRpcMessage = {
    jsonrpc: "2.0",
    id?: JsonRpcId,
    method?: string,
    params?: any,
    result?: any,
    error?: any,
};

const setDecorations = StateEffect.define<DecorationSet>({});

export abstract class LspClient {
    public id: number;
    public outboundRequests: Map<JsonRpcId, OutboundRequest>;

    public rootUri: string;
    public workspaceFolders: LSP.WorkspaceFolder[];
    
    public autoClose?: boolean;
    public plugins: LspPlugin[];

    public isOpen: boolean;
    /**
     * Await initialization cycle completion
     */
    public initializePromise: Promise<void>;
    /**
     * Relies on initializePromise
     */
    public capabilities: LSP.ServerCapabilities<any>;

    constructor(rootUri: string, workspaceFolders: LSP.WorkspaceFolder[]) {
        this.id = 0;
        this.outboundRequests = new Map();

        this.rootUri = rootUri;
        this.workspaceFolders = workspaceFolders;

        this.autoClose = true;
        this.plugins = [];
        
        this.isOpen = false;
    }

    abstract sendMessage(data: JsonRpcMessage): Promise<void>;

    public async initialize() {
        const { capabilities } = await this.request<LSP.InitializeParams, LSP.InitializeResult>("initialize", {
            capabilities: {
                textDocument: {
                    publishDiagnostics: {},
                    semanticTokens: {
                        requests: {},
                        tokenTypes: Object.values(SemanticTokenTypes),
                        tokenModifiers: [],
	                    formats: ["relative"],
                        overlappingTokenSupport: true,
                    },
                    hover: {
                        dynamicRegistration: true,
                        contentFormat: ['plaintext', 'markdown'],
                    },
                    moniker: {},
                    synchronization: {
                        dynamicRegistration: true,
                        willSave: false,
                        didSave: false,
                        willSaveWaitUntil: false,
                    },
                    completion: {
                        dynamicRegistration: true,
                        completionItem: {
                            snippetSupport: false,
                            commitCharactersSupport: true,
                            documentationFormat: ['plaintext', 'markdown'],
                            deprecatedSupport: false,
                            preselectSupport: false,
                        },
                        contextSupport: false,
                    },
                    signatureHelp: {
                        dynamicRegistration: true,
                        signatureInformation: {
                            documentationFormat: ['plaintext', 'markdown'],
                        },
                    },
                    declaration: {
                        dynamicRegistration: true,
                        linkSupport: true,
                    },
                    definition: {
                        dynamicRegistration: true,
                        linkSupport: true,
                    },
                    typeDefinition: {
                        dynamicRegistration: true,
                        linkSupport: true,
                    },
                    implementation: {
                        dynamicRegistration: true,
                        linkSupport: true,
                    },
                },
                workspace: {
                    configuration: true,
                },
            },
            initializationOptions: null,
            processId: null,
            rootUri: this.rootUri,
            workspaceFolders: this.workspaceFolders,
        });
        this.capabilities = capabilities;
        this.notify("initialized", {});
        this.isOpen = true;
    }

    async close() {
        await this.request<void, void>("shutdown", void{});
        await this.notify<void>("exit", void{});
    }

    textDocumentDidOpen(params: LSP.DidOpenTextDocumentParams) {
        return this.notify("textDocument/didOpen", params);
    }

    textDocumentDidChange(params: LSP.DidChangeTextDocumentParams) {
        return this.notify("textDocument/didChange", params);
    }

    textDocumentHover(params: LSP.HoverParams) {
        return this.request<LSP.HoverParams, LSP.Hover | null>("textDocument/hover", params);
    }

    textDocumentCompletion(params: LSP.CompletionParams) {
        return this.request<LSP.CompletionParams, LSP.CompletionItem[] | LSP.CompletionList | null>("textDocument/completion", params);
    }

    textDocumentFoldingRange(params: LSP.FoldingRangeParams) {
        return this.request<LSP.FoldingRangeParams, LSP.FoldingRange[] | null>("textDocument/foldingRange", params);
    }

    textDocumentSemanticTokensFull(params: LSP.SemanticTokensParams) {
        return this.request<LSP.SemanticTokensParams, LSP.SemanticTokens | null>("textDocument/semanticTokens/full", params);
    }

    attachPlugin(plugin: LspPlugin) {
        this.plugins.push(plugin);
    }

    detachPlugin(plugin: LspPlugin) {
        const i = this.plugins.indexOf(plugin);
        if (i === -1) return;
        this.plugins.splice(i, 1);
        if (this.autoClose) this.close();
    }

    public async request<P, R>(method: string, params: P): Promise<R> {
        const id = this.id++;

        let resolve;
        let reject;
        let promise = new Promise((a, b) => {
            resolve = a;
            reject = b;
        });

        this.outboundRequests.set(id, {promise, resolve, reject})
        this.sendMessage({
            jsonrpc: "2.0",
            id,
            method,
            params,
        });

        const result = await promise;
        this.outboundRequests.delete(id);
        return result as R;
    }

    public async notify<P>(method: string, params: P) {
        await this.sendMessage({
            jsonrpc: "2.0",
            method,
            params,
        });
    }

    public handleMessage(message: JsonRpcMessage) {
        if (message.method === "workspace/configuration") {
            const configParams = message.params as LSP.ConfigurationParams;
            let resp: unknown[] = [];

            for (const item of configParams.items) {
                if (item.section === "zls.prefer_ast_check_as_child_process") {
                    resp.push(false);
                } else {
                    resp.push(null);
                }
            }

            this.sendMessage({
                jsonrpc: "2.0",
                id: message.id,
                result: resp,
            })

            return;
        }

        if (message.id !== undefined && message.method === undefined) {
            const req = this.outboundRequests.get(message.id);
            if (req) {
                if (message.error) req.reject(message.error);
                else req.resolve(message.result);
            } else {
                console.error("Got non-answer");
            }
        }

        for (const plugin of this.plugins)
            plugin.handleMessage(message);
    }

    public createPlugin(docUri: string, langId: string, allowHtmlContent: boolean) {
        let plugin: LspPlugin | null = null;

        const decorations = StateField.define<DecorationSet>({
            create() {
                return Decoration.none;
            },
            update(decorations, tr) {
                for (let e of tr.effects) if (e.is(setDecorations)) {
                    decorations = e.value;
                }
                return decorations;
            },
            provide: f => EditorView.decorations.from(f)
        });

        return [
            client.of(this),
            documentUri.of(docUri),
            languageId.of(langId),
            decorations.extension,
            ViewPlugin.define((view) => (plugin = new LspPlugin(view, allowHtmlContent)), {}),
            hoverTooltip(
                (view, pos) => plugin?.requestHoverTooltip(
                    view,
                    offsetToPos(view.state.doc, pos)
                ) ?? null
            ),
            foldService.of((state, lineStart, lineEnd) => {
                const startLine = state.doc.lineAt(lineStart);
                const range = plugin?.foldingRangeMap.get(startLine.number - 1);
                if (range) {
                    if (range.endLine > state.doc.lines) return null;
                    const endLine = state.doc.line(range.endLine + 1);
                    return {from: range.startCharacter != undefined ? lineStart + range.startCharacter : startLine.to, to: range.endCharacter != undefined ? endLine.from + range.endCharacter : endLine.to};
                }
                
                return null;
            }),
            
            autocompletion({
                override: [
                    async (context) => {
                        if (plugin == null) return null;

                        const { state, pos, explicit } = context;
                        const line = state.doc.lineAt(pos);
                        let trigKind: CompletionTriggerKind =
                            CompletionTriggerKind.Invoked;
                        let trigChar: string | undefined;
                        if (
                            !explicit &&
                            plugin.client.capabilities?.completionProvider?.triggerCharacters?.includes(
                                line.text[pos - line.from - 1]
                            )
                        ) {
                            trigKind = CompletionTriggerKind.TriggerCharacter;
                            trigChar = line.text[pos - line.from - 1];
                        }
                        if (
                            trigKind === CompletionTriggerKind.Invoked &&
                            !context.matchBefore(/\w+$/)
                        ) {
                            return null;
                        }
                        return await plugin.requestCompletion(
                            context,
                            offsetToPos(state.doc, pos),
                            {
                                triggerKind: trigKind,
                                triggerCharacter: trigChar,
                            }
                        );
                    },
                ],
            }),
            Prec.highest(
                keymap.of([{
                    key: "Mod-s",
                    run(view) {
                        plugin!.requestFormat(view);
                        return true;
                    }
                }])
            )
        ];
    }
}

class LspPlugin implements PluginValue {
    public client: LspClient;

    private documentUri: string;
    private languageId: string;
    private documentVersion: number;
    
    public decorations: DecorationSet;
    public foldingRangeMap: Map<number, LSP.FoldingRange>;

    constructor(private view: EditorView, private allowHtmlContent: boolean) {
        this.client = this.view.state.facet(client);
        this.documentUri = this.view.state.facet(documentUri);
        this.languageId = this.view.state.facet(languageId);
        this.documentVersion = 0;

        this.decorations = Decoration.none;
        this.foldingRangeMap = new Map();

        this.client.attachPlugin(this);

        this.initialize({
            documentText: this.view.state.doc.toString(),
        });
    }

    update(update: ViewUpdate) {
        if (!update.docChanged) return;
        this.foldingRangeMap.clear();
        (async () => {
            await this.sendChange({
                documentText: this.view.state.doc.toString(),
            });
            await this.updateDecorations();
            await this.updateFoldingRanges();
        })();
    }

    destroy() {
        this.client.detachPlugin(this);
    }

    async initialize({ documentText }: { documentText: string }) {
        if (this.client.initializePromise) {
            await this.client.initializePromise;
        }
        this.client.textDocumentDidOpen({
            textDocument: {
                uri: this.documentUri,
                languageId: this.languageId,
                text: documentText,
                version: this.documentVersion,
            }
        });
        await this.updateDecorations();
        await this.updateFoldingRanges();
    }

    async sendChange({ documentText }: { documentText: string }) {
        if (!this.client.isOpen) return;
        try {
            await this.client.textDocumentDidChange({
                textDocument: {
                    uri: this.documentUri,
                    version: this.documentVersion++,
                },
                contentChanges: [{ text: documentText }],
            });
        } catch (e) {
            console.error(e);
        }
    }

    public async updateDecorations(): Promise<void> {
        // TODO: Look into using incremental semantic
        // tokens using view.visibleRanges

        const semanticTokens = await this.client.textDocumentSemanticTokensFull({
            textDocument: {
                uri: this.documentUri,
            }
        });

        if (!semanticTokens) return console.log("No semantic tokens!");

        const tokenTypes = this.client.capabilities.semanticTokensProvider!.legend.tokenTypes;
        const tokenModifiers = this.client.capabilities.semanticTokensProvider!.legend.tokenModifiers;

        let builder = new RangeSetBuilder<Decoration>();

        let line = 0;
        let col = 0;

        const data = semanticTokens.data;
        for (let i = 0; i < data.length; i += 5) {
            const deltaLine = data[i];
            const deltaStartChar = data[i + 1];
            const length = data[i + 2];
            const tokenType = data[i + 3];
            const tokenModifierBitSet = data[i + 4];

            line += deltaLine;
            if (deltaLine == 0) { // same line
                col += deltaStartChar;
            } else {
                col = deltaStartChar;
            }
            
            let className = `st-${tokenTypes[tokenType]}`;

            {
                let value = tokenModifierBitSet;
                let index = 0;
                while (value != 0) {
                    if (value & 1) {
                        className += ` sm-${tokenModifiers[index]}`;
                    }
                    value = value >> 1;
                    index += 1;
                }
            }

            const l = this.view.state.doc.line(line + 1).from;
            builder.add(l + col, l + col + length, Decoration.mark({
                class: className,
            }));
        }
        this.decorations = builder.finish()
        this.view.dispatch({effects: [setDecorations.of(this.decorations)]});
    }

    public async updateFoldingRanges(): Promise<void> {
        const ranges = await this.client.textDocumentFoldingRange({
            textDocument: {
                uri: this.documentUri,
            }
        });

        this.foldingRangeMap.clear();
        if (ranges) {
            for (const range of ranges) {
                this.foldingRangeMap.set(range.startLine, range);
            }
        }
    }

    async requestFormat(view: EditorView): Promise<void> {
        const formattingResult = await this.client.request<LSP.DocumentFormattingParams, LSP.TextEdit[]>("textDocument/formatting", {
            options: {
                insertSpaces: true,
                tabSize: 4,
            },
            textDocument: {
                uri: this.documentUri,
            }
        });

        this.foldingRangeMap.clear();

        if (formattingResult) {
            const text = this.view.state.doc;

            let changes: ChangeSpec[] = [];
            for (const n of formattingResult) {
                changes.push({ from: posToOffset(text, n.range.start)!, to: posToOffset(text, n.range.end)!, insert: n.newText });
            }
            if (changes.length > 0) {
                this.view.dispatch({
                    changes,
                });
            }
        }

        await this.updateFoldingRanges();
    }

    async requestHoverTooltip(
        view: EditorView,
        { line, character }: { line: number; character: number }
    ): Promise<Tooltip | null> {
        if (!this.client.isOpen || !this.client.capabilities!.hoverProvider) return null;

        const result = await this.client.textDocumentHover({
            textDocument: { uri: this.documentUri },
            position: { line, character },
        });
        if (!result) return null;

        const { contents, range } = result;
        let pos = posToOffset(view.state.doc, { line, character })!;
        let end: number = pos;
        if (range) {
            pos = posToOffset(view.state.doc, range.start)!;
            end = posToOffset(view.state.doc, range.end) ?? end;
        }
        if (pos === null) return null;
        return { pos, end, create () {
            const dom = document.createElement("div");
            dom.textContent = formatContents(contents);
            return {dom};
        }, above: true };
    }

    async requestCompletion(
        context: CompletionContext,
        { line, character }: { line: number; character: number },
        {
            triggerKind,
            triggerCharacter,
        }: {
            triggerKind: CompletionTriggerKind;
            triggerCharacter: string | undefined;
        }
    ): Promise<CompletionResult | null> {
        if (!this.client.isOpen || !this.client.capabilities!.completionProvider) return null;
        this.sendChange({
            documentText: context.state.doc.toString(),
        });

        const result = await this.client.textDocumentCompletion({
            textDocument: { uri: this.documentUri },
            position: { line, character },
            context: {
                triggerKind,
                triggerCharacter,
            }
        });

        if (!result) return null;

        const items = 'items' in result ? result.items : result;

        let options = items.map(
            ({
                detail,
                label,
                kind,
                textEdit,
                documentation,
                sortText,
                filterText,
            }) => {
                const completion: Completion & {
                    filterText: string;
                    sortText?: string;
                    apply: string;
                } = {
                    label,
                    detail,
                    apply: textEdit?.newText ?? label,
                    type: kind && CompletionItemKindMap[kind].toLowerCase(),
                    sortText: sortText ?? label,
                    filterText: filterText ?? label,
                };
                if (documentation) {
                    completion.info = formatContents(documentation);
                }
                return completion;
            }
        );

        const [span, match] = prefixMatch(options);
        const token = context.matchBefore(match);
        let { pos } = context;

        if (token) {
            pos = token.from;
            const word = token.text.toLowerCase();
            if (/^\w+$/.test(word)) {
                options = options
                    .filter(({ filterText }) =>
                        filterText.toLowerCase().startsWith(word)
                    )
                    .sort(({ apply: a }, { apply: b }) => {
                        switch (true) {
                            case a.startsWith(token.text) &&
                                !b.startsWith(token.text):
                                return -1;
                            case !a.startsWith(token.text) &&
                                b.startsWith(token.text):
                                return 1;
                        }
                        return 0;
                    });
            }
        }
        return {
            from: pos,
            options,
        };
    }

    handleMessage(message: JsonRpcMessage) {
        try {
            switch (message.method) {
                case "textDocument/publishDiagnostics":
                    this.handleDiagnostics(message.params);
                    break;
            }
        } catch (error) {
            console.error(error);
        }
    }

    handleDiagnostics(params: PublishDiagnosticsParams) {
        if (params.uri !== this.documentUri) return;

        const diagnostics = params.diagnostics
            .map(({ range, message, severity }) => ({
                from: posToOffset(this.view.state.doc, range.start)!,
                to: posToOffset(this.view.state.doc, range.end)!,
                severity: ({
                    [DiagnosticSeverity.Error]: 'error',
                    [DiagnosticSeverity.Warning]: 'warning',
                    [DiagnosticSeverity.Information]: 'info',
                    [DiagnosticSeverity.Hint]: 'info',
                } as const)[severity!],
                message,
            }))
            .filter(({ from, to }) => from !== null && to !== null && from !== undefined && to !== undefined)
            .sort((a, b) => {
                switch (true) {
                    case a.from < b.from:
                        return -1;
                    case a.from > b.from:
                        return 1;
                }
                return 0;
            });

        this.view.dispatch(setDiagnostics(this.view.state, diagnostics));
    }
}

interface LanguageServerBaseOptions {
    rootUri: string | null;
    workspaceFolders: LSP.WorkspaceFolder[] | null;
    documentUri: string;
    languageId: string;
}

function posToOffset(doc: Text, pos: { line: number; character: number }) {
    if (pos.line >= doc.lines) return;
    const offset = doc.line(pos.line + 1).from + pos.character;
    if (offset > doc.length) return;
    return offset;
}

function offsetToPos(doc: Text, offset: number) {
    const line = doc.lineAt(offset);
    return {
        line: line.number - 1,
        character: offset - line.from,
    };
}

function formatContents(
    contents: LSP.MarkupContent | LSP.MarkedString | LSP.MarkedString[]
): string {
    if (Array.isArray(contents)) {
        return contents.map((c) => formatContents(c) + '\n\n').join('');
    } else if (typeof contents === 'string') {
        return contents;
    } else {
        return contents.value;
    }
}

function toSet(chars: Set<string>) {
    let preamble = '';
    let flat = Array.from(chars).join('');
    const words = /\w/.test(flat);
    if (words) {
        preamble += '\\w';
        flat = flat.replace(/\w/g, '');
    }
    return `[${preamble}${flat.replace(/[^\w\s]/g, '\\$&')}]`;
}

function prefixMatch(options: Completion[]) {
    const first = new Set<string>();
    const rest = new Set<string>();

    for (const { apply } of options) {
        const [initial, ...restStr] = apply as string;
        first.add(initial);
        for (const char of restStr) {
            rest.add(char);
        }
    }

    const source = toSet(first) + toSet(rest) + '*$';
    return [new RegExp('^' + source), new RegExp(source)];
}
