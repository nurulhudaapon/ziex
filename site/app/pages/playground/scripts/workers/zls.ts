import { WASI, PreopenDirectory, Fd, ConsoleStdout } from "@bjorn3/browser_wasi_shim";
import { getLatestZigArchive, getZxArchive, fetchWithCache } from "../utils";

declare const ZLS_VERSION: string;

class Stdio extends Fd {
    constructor() {
        super();
    }

    fd_write(slice: Uint8Array): { ret: number; nwritten: number } {
        throw new Error("Cannot write");
    }

    fd_read(size: number): { ret: number; data: Uint8Array; } {
        throw new Error("Cannot read");
    }
}

let instance: any;
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

function prepareMessage(message: string): string {
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

function sendMessage(message: string) {
    const prepared = prepareMessage(message);
    const inputMessageBuffer = new TextEncoder().encode(prepared);
    const ptr = instance.exports.allocMessage(inputMessageBuffer.length);
    new Uint8Array(instance.exports.memory.buffer).set(inputMessageBuffer, ptr);
    instance.exports.call();

    const outputMessageCount = instance.exports.outputMessageCount();
    for (let i = 0; i < outputMessageCount; i++) {
        const start = instance.exports.outputMessagePtr(i);
        const end = start + instance.exports.outputMessageLen(i);
        const outputMessageBuffer = new Uint8Array(instance.exports.memory.buffer).slice(start, end);
        postMessage(new TextDecoder().decode(outputMessageBuffer));
    }
}

onmessage = (event) => {
    if (instance) {
        sendMessage(event.data);
    } else {
        bufferedMessages.push(event.data);
    }
};

(async () => {
    const libDirectory = await getLatestZigArchive();
    const zxDirectory = await getZxArchive();

    const fds = [
        new Stdio(), // stdin
        new Stdio(), // stdout
        ConsoleStdout.lineBuffered((line) => postMessage(JSON.stringify({ stderr: line }))), // stderr
        new PreopenDirectory(".", new Map([
            ["zx", zxDirectory],
        ])),
        new PreopenDirectory("/zx", zxDirectory.contents),
        new PreopenDirectory("/lib", libDirectory.contents),
        new PreopenDirectory("/cache", new Map()),
    ];
    const wasii = new WASI(["zls.wasm"], [], fds, { debug: false });

    const response = await fetchWithCache(`/assets/playground/zls-${ZLS_VERSION}.wasm`);
    const { instance: localInstance } = await WebAssembly.instantiateStreaming(response, {
        "wasi_snapshot_preview1": wasii.wasiImport,
    });

    // @ts-ignore
    wasii.inst = localInstance;

    // @ts-ignore
    localInstance.exports.createServer();

    instance = localInstance;

    for (const bufferedMessage of bufferedMessages) {
        sendMessage(bufferedMessage);
    }
})();
