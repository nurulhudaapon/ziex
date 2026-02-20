import { WASI, PreopenDirectory, Fd, File, OpenFile, Inode } from "@bjorn3/browser_wasi_shim";
import { getLatestZigArchive, getZxArchive, stderrOutput, stdoutOutput, fetchWithCache } from "../utils";

let currentlyRunning = false;
let compiledModule: WebAssembly.Module | null = null;

async function runZxTranspile(filename: string, content: string) {
    if (currentlyRunning) return;
    currentlyRunning = true;

    const zxDirectory = await getZxArchive();
    const libDirectory = await getLatestZigArchive();

    let args = [
        "zx.wasm",
        "transpile",
        "/codes/" + filename
    ];
    let env: string[] = [];

    const fileContents = new Map<string, Inode>();
    fileContents.set(filename, new File(new TextEncoder().encode(content)));
    fileContents.set("zx", zxDirectory);

    let fds = [
        new OpenFile(new File([])), // stdin
        stdoutOutput(), // stdout
        stderrOutput(), // stderr
        new PreopenDirectory("/codes", fileContents),
        new PreopenDirectory("/lib", libDirectory.contents),
        new PreopenDirectory("/cache", new Map()),
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
        // const stdout = wasi.fds[1] as OpenFile;

        // const stdoutcontent = new TextDecoder().decode(stdout.file.data);
        // console.log("ZX Transpile stdout:", stdoutcontent);
        // if (stdoutcontent) {
        //     postMessage({ stdout: stdout. });
        // }
        // if (exitCode == 0) {
        //     const cwd = wasi.fds[3] as PreopenDirectory;
        //     // Assume output is filename with .zig extension
        //     console.log(wasi);
        //     const zigFilename = filename.replace(/\.zx$/, ".zig");
        //     const transpiled = cwd.dir.contents.get(zigFilename);
        //     if (transpiled && transpiled instanceof File) {
        //         postMessage({ filename: zigFilename, transpiled: new TextDecoder().decode(transpiled.data) });
        //     }
        // }
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
        runZxTranspile(event.data.filename, event.data.content);
    }
}
