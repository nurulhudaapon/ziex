export type PlaygroundFilesMap = Record<string, string>;


const ZX_IMPORT_LINE = 'const zx = @import("zx");';
const STD_IMPORT_LINE = 'const std = @import("std");';

function ensureTopLevelZxImport(code: string): string {
    const hasTopLevelImport = code
        .split(/\r?\n/)
        .some((line) => /^const\s+zx\s*=\s*@import\("zx"\);\s*$/.test(line));

    if (hasTopLevelImport) {
        return code;
    }

    const normalized = code.replace(/\s+$/, "");
    return `${normalized}\n\n${ZX_IMPORT_LINE}`;
}

function ensureTopLevelStdImport(code: string): string {
    // Check if code uses std.*
    const usesStd = /std\.\w+/m.test(code);
    
    if (!usesStd) {
        return code;
    }

    // Check if std import already exists
    const hasTopLevelImport = code
        .split(/\r?\n/)
        .some((line) => /^const\s+std\s*=\s*@import\("std"\);\s*$/.test(line));

    if (hasTopLevelImport) {
        return code;
    }

    const normalized = code.replace(/\s+$/, "");
    return `${normalized}\n\n${STD_IMPORT_LINE}`;
}

export function createDocsSnippetFiles(code: string, filename = "Playground.zx"): PlaygroundFilesMap {
    void filename;
    let processedCode = code;
    // Apply both import checks - order matters for proper formatting
    processedCode = ensureTopLevelStdImport(processedCode);
    processedCode = ensureTopLevelZxImport(processedCode);
    
    return {
        "Playground.zx": processedCode,
    };
}

export async function encodeFilesToQuery(filesMap: PlaygroundFilesMap): Promise<string> {
    const json = JSON.stringify(filesMap);
    const stream = new Blob([json]).stream().pipeThrough(new CompressionStream("deflate"));
    const buffer = await new Response(stream).arrayBuffer();

    let binString = "";
    const bytes = new Uint8Array(buffer);
    const CHUNK_SIZE = 0x8000;
    for (let i = 0; i < bytes.length; i += CHUNK_SIZE) {
        binString += String.fromCharCode.apply(null, Array.from(bytes.subarray(i, i + CHUNK_SIZE)));
    }

    const b64 = btoa(binString);
    return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function decodeFilesFromQuery(query: string): Promise<PlaygroundFilesMap | null> {
    try {
        let b64 = query.replace(/-/g, "+").replace(/_/g, "/");
        while (b64.length % 4) {
            b64 += "=";
        }

        const binString = atob(b64);
        const bytes = Uint8Array.from(binString, (m) => m.codePointAt(0) ?? 0);
        const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
        const text = await new Response(stream).text();

        return JSON.parse(text) as PlaygroundFilesMap;
    } catch {
        return null;
    }
}

export async function createPlaygroundShareUrl(filesMap: PlaygroundFilesMap, baseUrl: string): Promise<string> {
    const encoded = await encodeFilesToQuery(filesMap);
    return `${baseUrl}#data=${encoded}`;
}