import { compile, optimize } from "@tailwindcss/node";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { dirname } from "path";

type TailwindBuildConfig = {
    input: string;
    output: string;
    minify?: boolean;
    optimize?: boolean;
    map?: boolean;
    base?: string;
};

type TailwindBuild = {
    id: number;
    name: string;
    config: TailwindBuildConfig;
};

type BuildEvent =
    | { id: number; name: string; type: "start" }
    | { id: number; name: string; type: "result"; success: boolean; output: string; dependencies: string[] }
    | { id: number; name: string; type: "error"; error: string }
    | { id: number; name: string; type: "end" };

function writeLine(event: BuildEvent): void {
    process.stdout.write(JSON.stringify(event) + "\n");
}

async function runBuild({ id, name, config }: TailwindBuild, index: number): Promise<void> {
    id = id ?? index;

    writeLine({ id, type: "start", name });
    try {
        const css = readFileSync(config.input, "utf-8");
        const base = config.base ?? dirname(config.input);

        const dependencies: string[] = [];
        const compiler = await compile(css, {
            base,
            onDependency: (path) => dependencies.push(path),
        });

        const built = compiler.build([]);

        let result = built;
        if (config.optimize || config.minify) {
            const optimized = optimize(result, {
                file: config.output,
                minify: config.minify,
            });
            result = optimized.code;
        }

        mkdirSync(dirname(config.output), { recursive: true });
        writeFileSync(config.output, result);

        writeLine({ id, type: "result", name, success: true, output: config.output, dependencies });
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
    const builds: TailwindBuild[] = await Bun.stdin.json();
    await Promise.allSettled(builds.map(runBuild));
}

main().catch((err) => {
    process.stderr.write(`ziex-plugin-tailwindcss: fatal: ${err}\n`);
    process.exit(1);
});
