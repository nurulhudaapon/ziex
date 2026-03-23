import { build } from "bun";

type BunBuilds = {
    id: number;
    name: string;
    config: Bun.BuildConfig;
};

type BunBuildEvent =
    | {id: number, name: string; type: "start" }
    | { id: number, name: string; type: "result"; success: boolean; outputs: string[]; logs: Array<BuildMessage | ResolveMessage> }
    | { id: number, name: string; type: "error"; error: string }
    | { id: number, name: string; type: "end" };

function writeLine(event: BunBuildEvent): void {
    process.stdout.write(JSON.stringify(event) + "\n");
}

async function runBuild({ id, name, config }: BunBuilds, index: number): Promise<void> {
     id = id ?? index;

    writeLine({ id, type: "start", name });
    try {
        const result = await build(config);
        writeLine({
            id, 
            type: "result",
            name,
            success: result.success,
            outputs: result.outputs.map((o) => o.path),
            logs: result.logs,
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
