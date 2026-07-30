import { WASI, PreopenDirectory, Fd, ConsoleStdout } from "@bjorn3/browser_wasi_shim";
import { getLatestZigArchive, getZxArchive, fetchWithCache } from "../utils";

declare const VERSION: string;
declare const ZLS_VERSION: string;

type LspWasmExports = {
    memory: WebAssembly.Memory;
    createServer: () => void;
    allocMessage: (len: number) => number;
    call: () => void;
    outputMessageCount: () => number;
    outputMessagePtr: (index: number) => number;
    outputMessageLen: (index: number) => number;
};

type LspInstance = { exports: LspWasmExports };

class Stdio extends Fd {
    constructor() {
        super();
    }

    fd_write(_slice: Uint8Array): { ret: number; nwritten: number } {
        throw new Error("Cannot write");
    }

    fd_read(_size: number): { ret: number; data: Uint8Array } {
        throw new Error("Cannot read");
    }
}

let zxLsp: LspInstance | null = null;
let zls: LspInstance | null = null;
let ready = false;
let bufferedMessages: string[] = [];

function zxImportPathForUri(uri: string | undefined): string {
    if (!uri) return "zx/src/root.zig";
    const path = uri.replace(/^file:\/+/, "").replace(/^\//, "");
    const parts = path.split("/").filter(Boolean);
    const depth = Math.max(0, parts.length - 1);
    return `${"../".repeat(depth)}zx/src/root.zig`;
}

function rewriteZxImport(text: string, uri?: string): string {
    const resolved = zxImportPathForUri(uri);
    return text.replaceAll('@import("zx")', `@import("${resolved}")`);
}

/** Rewrite `@import("zx")` for ZLS only; ZX LSP sees the original source. */
function prepareForZls(message: string): string {
    try {
        const msg = JSON.parse(message);
        if (msg.method === "textDocument/didOpen" && typeof msg.params?.textDocument?.text === "string") {
            const uri = msg.params.textDocument.uri as string | undefined;
            msg.params.textDocument.text = rewriteZxImport(msg.params.textDocument.text, uri);
            return JSON.stringify(msg);
        }
        if (msg.method === "textDocument/didChange" && Array.isArray(msg.params?.contentChanges)) {
            const uri = msg.params?.textDocument?.uri as string | undefined;
            for (const change of msg.params.contentChanges) {
                if (typeof change.text === "string") {
                    change.text = rewriteZxImport(change.text, uri);
                }
            }
            return JSON.stringify(msg);
        }
    } catch {
        // not a JSON LSP message
    }
    return message;
}

function callServer(instance: LspInstance, message: string): string[] {
    const inputMessageBuffer = new TextEncoder().encode(message);
    const ptr = instance.exports.allocMessage(inputMessageBuffer.length);
    new Uint8Array(instance.exports.memory.buffer).set(inputMessageBuffer, ptr);
    instance.exports.call();

    const outs: string[] = [];
    const outputMessageCount = instance.exports.outputMessageCount();
    for (let i = 0; i < outputMessageCount; i++) {
        const start = instance.exports.outputMessagePtr(i);
        const end = start + instance.exports.outputMessageLen(i);
        const outputMessageBuffer = new Uint8Array(instance.exports.memory.buffer).slice(start, end);
        outs.push(new TextDecoder().decode(outputMessageBuffer));
    }
    return outs;
}

function parseMessage(raw: string): any | null {
    try {
        return JSON.parse(raw);
    } catch {
        return null;
    }
}

function mergeInitialize(zxMsg: any | null, zlsMsg: any | null): any | null {
    if (!zxMsg && !zlsMsg) return null;
    if (!zxMsg) return zlsMsg;
    if (!zlsMsg) return zxMsg;
    if (zxMsg.error && !zlsMsg.error) return zlsMsg;
    if (zlsMsg.error && !zxMsg.error) return zxMsg;

    const zxResult = zxMsg.result ?? {};
    const zlsResult = zlsMsg.result ?? {};
    const zxCaps = zxResult.capabilities ?? {};
    const zlsCaps = zlsResult.capabilities ?? {};

    return {
        jsonrpc: "2.0",
        id: zxMsg.id ?? zlsMsg.id,
        result: {
            ...zlsResult,
            ...zxResult,
            capabilities: {
                ...zlsCaps,
                ...zxCaps,
                // Prefer ZLS where ZX left a capability unset/falsey but ZLS has it.
                hoverProvider: zxCaps.hoverProvider || zlsCaps.hoverProvider,
                documentFormattingProvider:
                    zxCaps.documentFormattingProvider || zlsCaps.documentFormattingProvider,
                textDocumentSync: zxCaps.textDocumentSync ?? zlsCaps.textDocumentSync,
                completionProvider: zlsCaps.completionProvider ?? zxCaps.completionProvider,
                definitionProvider: zlsCaps.definitionProvider ?? zxCaps.definitionProvider,
                referencesProvider: zlsCaps.referencesProvider ?? zxCaps.referencesProvider,
                documentSymbolProvider: zlsCaps.documentSymbolProvider ?? zxCaps.documentSymbolProvider,
                semanticTokensProvider: zlsCaps.semanticTokensProvider ?? zxCaps.semanticTokensProvider,
                foldingRangeProvider: zlsCaps.foldingRangeProvider ?? zxCaps.foldingRangeProvider,
            },
            serverInfo: {
                name: "ziex",
                version: zxResult.serverInfo?.version ?? zlsResult.serverInfo?.version,
            },
        },
    };
}

/** Prefer a non-null ZX result (HTML hover, ZX format); otherwise fall through to ZLS. */
function preferResponse(zxMsg: any | null, zlsMsg: any | null): any | null {
    if (zxMsg && !zxMsg.error && zxMsg.result != null) return zxMsg;
    if (zlsMsg) return zlsMsg;
    return zxMsg;
}

function partitionOutputs(raws: string[]): { responses: Map<string | number, any>; others: string[] } {
    const responses = new Map<string | number, any>();
    const others: string[] = [];
    for (const raw of raws) {
        const msg = parseMessage(raw);
        if (!msg) continue;
        // Client-bound response (has id, no method).
        if (msg.id !== undefined && msg.method === undefined) {
            responses.set(msg.id, msg);
            continue;
        }
        others.push(raw);
    }
    return { responses, others };
}

function tagPublishDiagnostics(raw: string, server: "zx" | "zls"): string {
    const msg = parseMessage(raw);
    if (!msg || msg.method !== "textDocument/publishDiagnostics") return raw;
    msg.params = msg.params ?? {};
    // Non-standard field so the client can clear per-server without wiping the other.
    msg.params.ziexSource = server;
    if (Array.isArray(msg.params.diagnostics)) {
        for (const d of msg.params.diagnostics) {
            if (!d.source) d.source = server;
        }
    }
    return JSON.stringify(msg);
}

function sendMessage(message: string) {
    const zxOuts = zxLsp ? callServer(zxLsp, message).map((r) => tagPublishDiagnostics(r, "zx")) : [];
    const zlsOuts = zls ? callServer(zls, prepareForZls(message)).map((r) => tagPublishDiagnostics(r, "zls")) : [];

    const zxPart = partitionOutputs(zxOuts);
    const zlsPart = partitionOutputs(zlsOuts);

    // Forward notifications and server→client requests immediately.
    for (const raw of [...zxPart.others, ...zlsPart.others]) {
        postMessage(raw);
    }

    const ids = new Set<string | number>([
        ...zxPart.responses.keys(),
        ...zlsPart.responses.keys(),
    ]);

    let incomingMethod: string | undefined;
    try {
        incomingMethod = JSON.parse(message)?.method;
    } catch {
        incomingMethod = undefined;
    }

    for (const id of ids) {
        const zxMsg = zxPart.responses.get(id) ?? null;
        const zlsMsg = zlsPart.responses.get(id) ?? null;
        const merged =
            incomingMethod === "initialize"
                ? mergeInitialize(zxMsg, zlsMsg)
                : preferResponse(zxMsg, zlsMsg);
        if (merged) postMessage(JSON.stringify(merged));
    }
}

onmessage = (event) => {
    if (ready) {
        sendMessage(event.data);
    } else {
        bufferedMessages.push(event.data);
    }
};

async function instantiateLsp(
    name: string,
    url: string,
    fds: Fd[],
): Promise<LspInstance> {
    const wasii = new WASI([name], [], fds, { debug: false });
    const response = await fetchWithCache(url);
    const { instance } = await WebAssembly.instantiateStreaming(response, {
        wasi_snapshot_preview1: wasii.wasiImport,
    });
    // @ts-ignore
    wasii.inst = instance;
    const lsp = instance as unknown as LspInstance;
    lsp.exports.createServer();
    return lsp;
}

function makeFds(libDirectory: PreopenDirectory, zxDirectory: PreopenDirectory): Fd[] {
    return [
        new Stdio(),
        new Stdio(),
        ConsoleStdout.lineBuffered((line) => postMessage(JSON.stringify({ stderr: line }))),
        new PreopenDirectory(".", new Map([["zx", zxDirectory]])),
        new PreopenDirectory("/zx", zxDirectory.contents),
        new PreopenDirectory("/lib", libDirectory.contents),
        new PreopenDirectory("/cache", new Map()),
    ];
}

(async () => {
    const libDirectory = await getLatestZigArchive();
    const zxDirectory = await getZxArchive();

    const results = await Promise.allSettled([
        instantiateLsp("zx.wasm", `/assets/playground/zx-${VERSION}.wasm`, makeFds(libDirectory, zxDirectory)),
        instantiateLsp(`zls-${ZLS_VERSION}.wasm`, `/assets/playground/zls-${ZLS_VERSION}.wasm`, makeFds(libDirectory, zxDirectory)),
    ]);

    if (results[0].status === "fulfilled") {
        zxLsp = results[0].value;
    } else {
        console.error("ZX LSP failed to load", results[0].reason);
        postMessage(JSON.stringify({ stderr: `ZX LSP failed: ${results[0].reason}` }));
    }

    if (results[1].status === "fulfilled") {
        zls = results[1].value;
    } else {
        console.error("ZLS failed to load", results[1].reason);
        postMessage(JSON.stringify({ stderr: `ZLS failed: ${results[1].reason}` }));
    }

    if (!zxLsp && !zls) {
        postMessage(JSON.stringify({ stderr: "No language servers available" }));
        return;
    }

    ready = true;
    for (const bufferedMessage of bufferedMessages) {
        sendMessage(bufferedMessage);
    }
    bufferedMessages = [];
})();
