const esbuild = require("esbuild");
const { readFileSync, existsSync } = require("fs");
const { resolve } = require("path");

function writeLine(event) {
    process.stdout.write(JSON.stringify(event) + "\n");
}

/**
 * Support Bun-style text imports: `import src from "./x.zig" with { type: "text" }`.
 * esbuild rejects the `type: "text"` attribute natively, so resolve those imports
 * ourselves and hand the file to esbuild's built-in `text` loader.
 */
const textTypeAttributePlugin = {
    name: "text-type-attribute",
    setup(build) {
        build.onResolve({ filter: /.*/ }, (args) => {
            if (args.with && args.with.type === "text") {
                return { path: resolve(args.resolveDir, args.path), namespace: "text-attr" };
            }
        });
        build.onLoad({ filter: /.*/, namespace: "text-attr" }, (args) => {
            return { contents: readFileSync(args.path, "utf8"), loader: "text", watchFiles: [args.path] };
        });
    },
};

/**
 * Translate the Zig-side config (mirror of EsbuildBuildConfig) into esbuild's
 * BuildOptions. `outdir` is injected by the runner exe from the --outdir CLI arg.
 */
function toBuildOptions(config) {
    const options = {
        entryPoints: config.entrypoints,
        outdir: config.outdir,
        // Always emit a metafile so we can report transitive dependencies for caching.
        metafile: true,
        bundle: config.bundle ?? true,
        plugins: [textTypeAttributePlugin],
    };

    if (config.platform) options.platform = config.platform;
    if (config.format) options.format = config.format;
    if (config.minify != null) options.minify = config.minify;
    if (config.splitting != null) options.splitting = config.splitting;
    if (config.publicPath) options.publicPath = config.publicPath;
    if (config.external) options.external = config.external;
    if (config.target && config.target.length > 0) options.target = config.target;
    if (config.define) options.define = config.define;

    switch (config.sourcemap) {
        case "linked": options.sourcemap = "linked"; break;
        case "inline": options.sourcemap = "inline"; break;
        case "external": options.sourcemap = "external"; break;
        case "both": options.sourcemap = "both"; break;
        case "none":
        case undefined:
            break;
        default: options.sourcemap = config.sourcemap;
    }

    return options;
}

/**
 * Turn esbuild metafile input keys into real, absolute file paths for the dep file.
 * Plugin-loaded inputs are keyed as `namespace:path` (e.g. our `text-attr:/abs/x.zig`);
 * strip the namespace and keep only entries that point at a file that exists on disk,
 * so the Make-style dep file zig reads never references a phantom path.
 */
function collectDependencies(inputs) {
    const deps = new Set();
    for (const key of Object.keys(inputs)) {
        let path = key;
        const colon = path.indexOf(":");
        // A leading `namespace:` prefix (not a Windows drive letter) marks a
        // plugin-resolved input; the part after it is the real path.
        if (colon > 1) path = path.slice(colon + 1);
        const abs = resolve(path);
        if (existsSync(abs)) deps.add(abs);
    }
    return [...deps];
}

async function runBuild({ id, name, config }, index) {
    id = id ?? index;

    writeLine({ id, type: "start", name });
    try {
        const result = await esbuild.build(toBuildOptions(config));

        const dependencies = result.metafile
            ? collectDependencies(result.metafile.inputs)
            : [];

        writeLine({
            id,
            type: "result",
            name,
            success: (result.errors?.length ?? 0) === 0,
            dependencies,
        });
    } catch (err) {
        writeLine({
            id,
            type: "error",
            name,
            error: err instanceof Error ? err.message : String(err),
        });
    } finally {
        writeLine({ id, type: "end", name });
    }
}

async function main() {
    // Read stdin as JSON (Node.js compatible)
    const chunks = [];
    for await (const chunk of process.stdin) {
        chunks.push(chunk);
    }
    const builds = JSON.parse(Buffer.concat(chunks).toString("utf-8"));
    await Promise.allSettled(builds.map(runBuild));
}

main().catch((err) => {
    process.stderr.write(`ziex-plugin-esbuild: fatal: ${err}\n`);
    process.exit(1);
});
