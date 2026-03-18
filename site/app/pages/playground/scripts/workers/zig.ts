import { WASI, PreopenDirectory, Fd, File, OpenFile, Inode } from "@bjorn3/browser_wasi_shim";
import { getLatestZigArchive, getZxArchive, stderrOutput, fetchWithCache } from "../utils";

let currentlyRunning = false;
let compiledModule: WebAssembly.Module | null = null;

async function run(files: { [filename: string]: string }) {
    if (currentlyRunning) return;

    currentlyRunning = true;

    const zxDirectory = await getZxArchive();
    const libDirectory = await getLatestZigArchive();


    // -fno-llvm -fno-lld is set explicitly to ensure the native WASM backend is
    // used in preference to LLVM. This may be removable once the non-LLVM
    // backends become more mature.
    let args = [
        "zig.wasm",
        "build-exe",

        // Old
        // "main.zig",

        // New ----
        "--dep",
        "zx",
        "-Mroot=main.zig",
        "-Mzx=zx/src/root.zig",

        "--name",
        "main",
        // ----

        "-fno-llvm",
        "-fno-lld",
        "-fno-ubsan-rt",
        "-fno-entry", // prevent the native webassembly backend from adding a start function to the module 
    ];
    let env: string[] = [];

    const fileContents = new Map<string, Inode>();
    for (const [filename, content] of Object.entries(files)) {
        fileContents.set(filename, new File(new TextEncoder().encode(content)));
    }
    fileContents.set("zx", zxDirectory);

    let fds = [
        new OpenFile(new File([])), // stdin
        stderrOutput(), // stdout
        stderrOutput(), // stderr
        new PreopenDirectory(".", fileContents),
        new PreopenDirectory("/lib", libDirectory.contents),
        new PreopenDirectory("/cache", new Map()),
    ] satisfies Fd[];
    let wasi = new WASI(args, env, fds, { debug: false });

    if (!compiledModule) {
        const response = await fetchWithCache("/assets/playground/zig.wasm");
        compiledModule = await WebAssembly.compileStreaming(response);
    }
    const instance = await WebAssembly.instantiate(compiledModule, {
        "wasi_snapshot_preview1": wasi.wasiImport,
    });

    try {
        // @ts-ignore
        const exitCode = wasi.start(instance);

        if (exitCode == 0) {
            const cwd = wasi.fds[3] as PreopenDirectory;
            const mainWasm = cwd.dir.contents.get("main.wasm") as File | undefined;
            if (mainWasm) {
                postMessage({ compiled: mainWasm.data });
            }
        }
    } catch (err) {
        postMessage({
            stderr: `${err}`,
        });
        postMessage({ failed: true });
    }

    currentlyRunning = false;
}

onmessage = (event) => {
    if (event.data.files) {
        run(event.data.files);
    }
}
