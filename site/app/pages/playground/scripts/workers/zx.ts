import { File, Inode, OpenFile, PreopenDirectory, ConsoleStdout, WASI } from "@bjorn3/browser_wasi_shim";
import { fetchWithCache } from "../utils";

declare const VERSION: string;
let currentlyRunning = false;
let compiledModule: WebAssembly.Module | null = null;

async function run(filename: string, content: string, subcommand?: string) {
    if (currentlyRunning) {
        postMessage({
            stderr: "zx worker is busy",
            failed: true,
        });
        return;
    }
    currentlyRunning = true;

    const cmd = subcommand || "transpile";
    const args =
        cmd === "fmt"
            ? ["zx.wasm", "fmt", "--stdout", "/codes/" + filename]
            : ["zx.wasm", cmd, "/codes/" + filename];
    const env: string[] = [];

    const fileContents = new Map<string, Inode>();
    fileContents.set(filename, new File(new TextEncoder().encode(content)));

    let stdout = "";
    let stderr = "";
    const stdoutDec = new TextDecoder("utf-8", { fatal: false });
    const stderrDec = new TextDecoder("utf-8", { fatal: false });

    const fds = [
        new OpenFile(new File([])), // stdin
        new ConsoleStdout((buffer) => {
            stdout += stdoutDec.decode(buffer, { stream: true });
        }),
        new ConsoleStdout((buffer) => {
            stderr += stderrDec.decode(buffer, { stream: true });
        }),
        new PreopenDirectory("/codes", fileContents),
    ];
    const wasi = new WASI(args, env, fds, { debug: false });

    if (!compiledModule) {
        const response = await fetchWithCache(`/assets/playground/zx-${VERSION}.wasm`);
        compiledModule = await WebAssembly.compileStreaming(response);
    }
    const instance = await WebAssembly.instantiate(compiledModule, {
        "wasi_snapshot_preview1": wasi.wasiImport,
    });

    try {
        // @ts-ignore
        const exitCode = wasi.start(instance);
        stdout += stdoutDec.decode();
        stderr += stderrDec.decode();

        if (exitCode !== 0) {
            postMessage({
                stderr: stderr || `zx exited with code ${exitCode}`,
                failed: true,
            });
        } else {
            postMessage({ stdout });
        }
    } catch (err) {
        postMessage({
            stderr: stderr ? `${stderr}\n${err}` : `${err}`,
            failed: true,
        });
    }
    currentlyRunning = false;
}

onmessage = (event) => {
    if (event.data.filename && event.data.content) {
        run(event.data.filename, event.data.content, event.data.subcommand);
    }
};
