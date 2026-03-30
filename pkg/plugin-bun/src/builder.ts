import { build } from "bun";

type BunBuilds = {
    id: number;
    name: string;
    config: Bun.BuildConfig;
};

type BunBuildEvent =
    | {id: number, name: string; type: "start" }
    | { id: number, name: string; type: "result"; success: boolean; outputs: string[]; logs: Array<BuildMessage | ResolveMessage>; dependencies: string[] }
    | { id: number, name: string; type: "error"; error: string }
    | { id: number, name: string; type: "end" };

function writeLine(event: BunBuildEvent): void {
    process.stdout.write(JSON.stringify(event) + "\n");
}

async function collectDependencies(entrypoints: string[]): Promise<string[]> {
    const seen = new Set<string>();
    const queue = [...entrypoints];

    while (queue.length > 0) {
        const file = queue.pop()!;
        if (seen.has(file)) continue;
        seen.add(file);

        try {
            const source = await Bun.file(file).text();
            const transpiler = new Bun.Transpiler({ loader: file.endsWith(".ts") || file.endsWith(".tsx") ? "tsx" : "js" });
            const imports = transpiler.scanImports(source);

            for (const imp of imports) {
                if (!imp.path.startsWith(".") && !imp.path.startsWith("/")) continue;
                try {
                    const resolved = Bun.resolveSync(imp.path, file.substring(0, file.lastIndexOf("/")));
                    queue.push(resolved);
                } catch {}
            }
        } catch {}
    }

    return [...seen];
}

async function runBuild({ id, name, config }: BunBuilds, index: number): Promise<void> {
     id = id ?? index;

    // Use metafile if available (Bun >= 1.4), fall back to scanImports
    config.metafile = true;

    writeLine({ id, type: "start", name });
    try {
        const result = await build(config);
        let dependencies: string[];
        if (result.metafile) {
            dependencies = Object.keys(result.metafile.inputs);
        } else {
            dependencies = await collectDependencies(
                (config.entrypoints as string[]).map(e => typeof e === "string" ? e : String(e))
            );
        }
        writeLine({
            id,
            type: "result",
            name,
            success: result.success,
            outputs: result.outputs.map((o) => o.path),
            logs: result.logs,
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
    const builds: BunBuilds[] = await  Bun.stdin.json();
    await Promise.allSettled(builds.map(runBuild));
}

main().catch((err) => {
    process.stderr.write(`ziex-plugin-bun: fatal: ${err}\n`);
    process.exit(1);
});
