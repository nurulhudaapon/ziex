import { File, Inode, OpenFile, PreopenDirectory, WASI } from "@bjorn3/browser_wasi_shim";
import { fetchWithCache, stderrOutput, stdoutOutput } from "../utils";

let currentlyRunning = false;
let compiledModule: WebAssembly.Module | null = null;

async function run(filename: string, content: string, subcommand?: string) {
    if (currentlyRunning) return;
    currentlyRunning = true;

    let args = [
        "zx.wasm",
        subcommand || "transpile",
        "/codes/" + filename
    ];
    let env: string[] = [];

    const fileContents = new Map<string, Inode>();
    fileContents.set(filename, new File(new TextEncoder().encode(content)));

    let fds = [
        new OpenFile(new File([])), // stdin
        stdoutOutput(), // stdout
        stderrOutput(), // stderr
        new PreopenDirectory("/codes", fileContents),
    ];
    let wasi = new WASI(args, env, fds, { debug: false });

    if (!compiledModule) {
        const response = await fetchWithCache("/assets/playground/zx.wasm");
        compiledModule = await WebAssembly.compileStreaming(response);
    }
    const instance = await WebAssembly.instantiate(compiledModule, {
        "wasi_snapshot_preview1": wasi.wasiImport,
    });

    try {
        // @ts-ignore
        const exitCode = wasi.start(instance);
    } catch (err) {
        postMessage({
            stderr: `${err}`,
            failed: true
        });
    }
    currentlyRunning = false;
}

onmessage = (event) => {
    if (event.data.filename && event.data.content) {
        run(event.data.filename, event.data.content, event.data.subcommand);
    }
}
