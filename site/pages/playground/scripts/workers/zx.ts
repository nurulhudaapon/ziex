import { WASI, PreopenDirectory, Fd, File, OpenFile, Inode } from "@bjorn3/browser_wasi_shim";
import { getLatestZigArchive, getZxArchive, stderrOutput } from "../utils";

let currentlyRunning = false;
async function run(files: { [filename: string]: string }) {
    if (currentlyRunning) return;

    currentlyRunning = true;

    const zxDirectory = await getZxArchive();
    const libDirectory = await getLatestZigArchive();

    // -fno-llvm -fno-lld is set explicitly to ensure the native WASM backend is
    // used in preference to LLVM. This may be removable once the non-LLVM
    // backends become more mature.
    let args = [
        "zx.wasm",
        "transpile",
    ];

    Object.keys(files).forEach(f => args.push("/codes/" + f));
    let env: string []= [];

    const fileContents = new Map<string, Inode>();
    for (const [filename, content] of Object.entries(files)) {
        fileContents.set(filename, new File(new TextEncoder().encode(content)));
    }
    fileContents.set("zx", zxDirectory);

    let fds = [
        new OpenFile(new File([])), // stdin
        stderrOutput(), // stdout
        stderrOutput(), // stderr
        new PreopenDirectory("/codes", fileContents),
        new PreopenDirectory("/lib", libDirectory.contents),
        new PreopenDirectory("/cache", new Map()),
    ] satisfies Fd[];
    let wasi = new WASI(args, env, fds, { debug: false });

    const { instance } = await WebAssembly.instantiateStreaming(fetch("/assets/playground/zig-out/bin/zx.wasm"), {
        "wasi_snapshot_preview1": wasi.wasiImport,
    });

    // postMessage({
    //     stderr: "Compiling...\n",
    // });

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
