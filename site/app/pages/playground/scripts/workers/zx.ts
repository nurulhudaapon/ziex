import { File, OpenFile, PreopenDirectory, ConsoleStdout, WASI, Directory } from "@bjorn3/browser_wasi_shim";
import { fetchWithCache } from "../utils";
import { nestPaths, flattenDirectory } from "../csr";

declare const VERSION: string;
let currentlyRunning = false;
let compiledModule: WebAssembly.Module | null = null;

function convertTree(node: Map<string, Map<string, unknown> | Uint8Array>): Directory {
    return new Directory(
        [...node.entries()].map(([key, value]) => {
            if (value instanceof Uint8Array) {
                return [key, new File(value)];
            }
            return [key, convertTree(value as Map<string, Map<string, unknown> | Uint8Array>)];
        }),
    );
}

function collectFromOut(outDir: Directory): { [name: string]: string } {
    const flat = flattenDirectory(outDir);
    const dec = new TextDecoder("utf-8", { fatal: false });
    const remapped: { [name: string]: string } = {};
    for (const [rel, data] of Object.entries(flat)) {
        if (!rel.endsWith(".zig") && !rel.endsWith(".zon")) continue;
        remapped[`app/${rel}`] = dec.decode(data);
    }
    return remapped;
}

async function run(
    files: { [filename: string]: string },
    opts: { path?: string; buildInjections?: string } = {},
) {
    if (currentlyRunning) {
        postMessage({
            stderr: "zx worker is busy",
            failed: true,
        });
        return;
    }
    currentlyRunning = true;

    const path = opts.path ?? "app";
    const outdir = "out";

    const args = [
        "zx.wasm",
        "transpile",
        path,
        "--outdir",
        outdir,
    ];
    if (opts.buildInjections) {
        args.push("--build-injections", opts.buildInjections);
        args.push("--manifest", `${outdir}/app.zon`);
    }

    const tree = nestPaths(files);
    if (!tree.has(outdir)) tree.set(outdir, new Map());
    const rootDir = convertTree(tree);
    const cwdPreopen = new PreopenDirectory(".", rootDir.contents);

    let stdout = "";
    let stderr = "";
    const stdoutDec = new TextDecoder("utf-8", { fatal: false });
    const stderrDec = new TextDecoder("utf-8", { fatal: false });

    const fds = [
        new OpenFile(new File([])),
        new ConsoleStdout((buffer) => {
            stdout += stdoutDec.decode(buffer, { stream: true });
        }),
        new ConsoleStdout((buffer) => {
            stderr += stderrDec.decode(buffer, { stream: true });
        }),
        cwdPreopen,
    ];
    const wasi = new WASI(args, [], fds, { debug: false });

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
            const outNode = cwdPreopen.dir.contents.get(outdir) as Directory | undefined;
            const remapped = outNode ? collectFromOut(outNode) : {};
            if (!remapped["app/app.zig"]) {
                const keys = outNode
                    ? Object.keys(flattenDirectory(outNode)).join(", ")
                    : "(missing out dir)";
                postMessage({
                    stderr:
                        (stderr ? stderr + "\n" : "") +
                        `transpile produced no app.zig (under out/: ${keys || "empty"})`,
                    failed: true,
                });
            } else {
                postMessage({ transpiled: remapped, stdout });
            }
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
    if (event.data.files) {
        run(event.data.files, {
            path: event.data.path,
            buildInjections: event.data.buildInjections,
        });
        return;
    }
    if (event.data.filename && event.data.content) {
        runSingle(event.data.filename, event.data.content, event.data.subcommand);
    }
};

async function runSingle(filename: string, content: string, subcommand?: string) {
    if (currentlyRunning) {
        postMessage({ stderr: "zx worker is busy", failed: true });
        return;
    }
    currentlyRunning = true;

    const cmd = subcommand || "transpile";
    const args =
        cmd === "fmt"
            ? ["zx.wasm", "fmt", "--stdout", filename]
            : ["zx.wasm", cmd, filename];

    const rootDir = convertTree(nestPaths({ [filename]: content }));
    const cwdPreopen = new PreopenDirectory(".", rootDir.contents);

    let stdout = "";
    let stderr = "";
    const stdoutDec = new TextDecoder("utf-8", { fatal: false });
    const stderrDec = new TextDecoder("utf-8", { fatal: false });

    const fds = [
        new OpenFile(new File([])),
        new ConsoleStdout((buffer) => {
            stdout += stdoutDec.decode(buffer, { stream: true });
        }),
        new ConsoleStdout((buffer) => {
            stderr += stderrDec.decode(buffer, { stream: true });
        }),
        cwdPreopen,
    ];
    const wasi = new WASI(args, [], fds, { debug: false });

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
