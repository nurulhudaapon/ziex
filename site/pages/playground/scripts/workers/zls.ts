import { WASI, PreopenDirectory, Fd, ConsoleStdout } from "@bjorn3/browser_wasi_shim";
import { getLatestZigArchive, fetchWithCache } from "../utils";

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

function sendMessage(message: string) {
    const inputMessageBuffer = new TextEncoder().encode(message);
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
    let libDirectory = await getLatestZigArchive();

    let args = ["zls.wasm"];
    let env: string[] = [];
    let fds = [
        new Stdio(), // stdin
        new Stdio(), // stdout
        ConsoleStdout.lineBuffered((line) => postMessage(JSON.stringify({ stderr: line }))), // stderr
        new PreopenDirectory(".", new Map([])),
        new PreopenDirectory("/lib", libDirectory.contents),
        new PreopenDirectory("/cache", new Map()),
    ];
    let wasii = new WASI(args, env, fds, { debug: false });

    const response = await fetchWithCache("/assets/playground/zls.wasm");
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
