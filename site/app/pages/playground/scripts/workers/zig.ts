import { WASI, PreopenDirectory, Fd, File, OpenFile, Directory } from "@bjorn3/browser_wasi_shim";
import { getLatestZigArchive, getZxArchive, stderrOutput, fetchWithCache } from "../utils";
import { nestPaths } from "../csr";

declare const ZIG_VERSION: string;

let currentlyRunning = false;
let compiledModule: WebAssembly.Module | null = null;

type CompileMode = "playground" | "app";
type CompileKind = "ssr" | "client";

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

function buildPlaygroundArgs(): string[] {
    return [
        "zig.wasm",
        "build-exe",
        "--dep",
        "zx",
        "-Mroot=main.zig",
        "-Mzx=zx/src/root.zig",
        "--name",
        "main",
        "libcompiler_rt.a",
        "-fno-compiler-rt",
        "-fno-entry",
    ];
}

function buildAppArgs(kind: CompileKind): string[] {
    const name = kind === "ssr" ? "ziex_ssr" : "ziex_client";
    const target = kind === "ssr" ? "wasm32-wasi" : "wasm32-freestanding";
    const optsMod = kind === "ssr"
        ? "stubs/zx_module_options_server.zig"
        : "stubs/zx_module_options_client.zig";

    const args = [
        "zig.wasm",
        "build-exe",
        "-target",
        target,
        "-O",
        "ReleaseSmall",
        "--dep",
        "zx",
        "-Mroot=app/main.zig",
        "--dep",
        "zx_module_options",
        "--dep",
        "zx_info",
        "--dep",
        "app",
        "--dep",
        "app_opts",
        "--dep",
        "manifest",
    ];

    if (kind === "client") args.push("--dep", "js");

    args.push(
        "-Mzx=zx/src/root.zig",
        `-Mzx_module_options=${optsMod}`,
        "-Mzx_info=stubs/zx_info.zig",
        "--dep",
        "zx",
        "-Mapp=app/app.zig",
        "-Mapp_opts=stubs/app_opts.zig",
        "-Mmanifest=stubs/manifest.zon",
    );

    if (kind === "client") args.push("-Mjs=js/src/main.zig");

    args.push(
        "--name",
        name,
        "libcompiler_rt.a",
        "-fno-compiler-rt",
        "--export-memory",
        "-rdynamic",
    );

    if (kind === "client") {
        args.push("-fno-entry", "--stack", "524288", "--max-memory=16777216");
    }

    return args;
}

async function ensureZigModule(): Promise<WebAssembly.Module> {
    if (!compiledModule) {
        const response = await fetchWithCache(`/assets/playground/zig-${ZIG_VERSION}.wasm`);
        compiledModule = await WebAssembly.compileStreaming(response);
    }
    return compiledModule;
}

async function compilePlayground(
    files: { [filename: string]: string },
    zxDirectory: Directory,
    libDirectory: Directory,
    libCompilerRt: ArrayBuffer,
): Promise<Uint8Array> {
    const args = buildPlaygroundArgs();
    const fileContents = new Map<string, File | Directory>();
    const enc = new TextEncoder();
    for (const [filename, content] of Object.entries(files)) {
        fileContents.set(filename, new File(enc.encode(content)));
    }
    fileContents.set("libcompiler_rt.a", new File(new Uint8Array(libCompilerRt)));
    fileContents.set("zx", zxDirectory);

    const wasi = new WASI(args, [], [
        new OpenFile(new File([])),
        stderrOutput(),
        stderrOutput(),
        new PreopenDirectory(".", fileContents),
        new PreopenDirectory("/lib", libDirectory.contents),
        new PreopenDirectory("/cache", new Map()),
    ] satisfies Fd[], { debug: false });

    const instance = await WebAssembly.instantiate(await ensureZigModule(), {
        wasi_snapshot_preview1: wasi.wasiImport,
    });
    // @ts-ignore
    const exitCode = wasi.start(instance);
    if (exitCode !== 0) throw new Error(`playground compile failed (exit ${exitCode})`);

    const cwd = wasi.fds[3] as PreopenDirectory;
    const wasmFile = cwd.dir.contents.get("main.wasm") as File | undefined;
    if (!wasmFile) throw new Error("playground compile produced no main.wasm");
    return wasmFile.data.slice();
}

async function compileAppOne(
    kind: CompileKind,
    files: { [filename: string]: string },
    zxDirectory: Directory,
    libDirectory: Directory,
    libCompilerRt: ArrayBuffer,
    jsDirectory: Directory | null,
): Promise<Uint8Array> {
    const args = buildAppArgs(kind);
    const tree = nestPaths(files);
    tree.set("libcompiler_rt.a", new Uint8Array(libCompilerRt));
    const cwdContents = convertTree(tree).contents;
    cwdContents.set("zx", zxDirectory);
    if (jsDirectory) cwdContents.set("js", jsDirectory);

    const wasi = new WASI(args, [], [
        new OpenFile(new File([])),
        stderrOutput(),
        stderrOutput(),
        new PreopenDirectory(".", cwdContents),
        new PreopenDirectory("/lib", libDirectory.contents),
        new PreopenDirectory("/cache", new Map()),
    ] satisfies Fd[], { debug: false });

    const instance = await WebAssembly.instantiate(await ensureZigModule(), {
        wasi_snapshot_preview1: wasi.wasiImport,
    });
    // @ts-ignore
    const exitCode = wasi.start(instance);
    if (exitCode !== 0) throw new Error(`${kind} compile failed (exit ${exitCode})`);

    const cwd = wasi.fds[3] as PreopenDirectory;
    const outName = kind === "ssr" ? "ziex_ssr.wasm" : "ziex_client.wasm";
    const wasmFile = cwd.dir.contents.get(outName) as File | undefined;
    if (!wasmFile) throw new Error(`${kind} compile produced no ${outName}`);
    return wasmFile.data.slice();
}

async function getJsArchive(): Promise<Directory> {
    const response = await fetchWithCache(`/assets/playground/jsz.tar.gz`);
    let arrayBuffer = await response.arrayBuffer();
    const magicNumber = new Uint8Array(arrayBuffer).slice(0, 2);
    if (magicNumber[0] == 0x1F && magicNumber[1] == 0x8B) {
        const ds = new DecompressionStream("gzip");
        arrayBuffer = await new Response(new Response(arrayBuffer).body!.pipeThrough(ds)).arrayBuffer();
    }
    const { untar } = await import("@andrewbranch/untar.js");
    const entries = untar(arrayBuffer);
    const root = new Map<string, Map<string, unknown> | Uint8Array>();
    for (const e of entries) {
        const path = e.filename.replace(/^\.\//, "");
        if (!path || path.endsWith("/")) continue;
        const parts = path.split("/");
        let cur = root;
        for (let i = 0; i < parts.length - 1; i++) {
            const seg = parts[i]!;
            let next = cur.get(seg);
            if (!(next instanceof Map)) {
                next = new Map();
                cur.set(seg, next);
            }
            cur = next as Map<string, Map<string, unknown> | Uint8Array>;
        }
        cur.set(parts[parts.length - 1]!, e.fileData);
    }
    return convertTree(root);
}

async function run(files: { [filename: string]: string }, mode: CompileMode) {
    if (currentlyRunning) return;
    currentlyRunning = true;

    try {
        const zxDirectory = await getZxArchive();
        const libDirectory = await getLatestZigArchive();
        const libCompilerRt = await (await fetchWithCache(`/assets/playground/libcompiler_rt-${ZIG_VERSION}.a`)).arrayBuffer();

        if (mode === "playground") {
            const wasm = await compilePlayground(files, zxDirectory, libDirectory, libCompilerRt);
            postMessage({ compiled: wasm });
        } else {
            const jsDirectory = await getJsArchive();
            const ssrWasm = await compileAppOne("ssr", files, zxDirectory, libDirectory, libCompilerRt, null);
            const clientWasm = await compileAppOne("client", files, zxDirectory, libDirectory, libCompilerRt, jsDirectory);
            postMessage({ compiled: { ssrWasm, clientWasm } });
        }
    } catch (err) {
        postMessage({ stderr: `${err}` });
        postMessage({ failed: true });
    }

    currentlyRunning = false;
}

onmessage = (event) => {
    if (event.data.files) {
        const mode: CompileMode = event.data.mode === "app" ? "app" : "playground";
        run(event.data.files, mode);
    }
};
