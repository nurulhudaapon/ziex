// @ts-ignore
import * as childProcess from "child_process";
// @ts-ignore
import * as util from "util";
import { ExtensionContext, window, workspace } from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions
} from "vscode-languageclient/node";

import { activateMultilineStringDecorator } from "./util/string";

let client: LanguageClient;
const execFile = util.promisify(childProcess.execFile);

export async function activate(context: ExtensionContext) {
  const lspCmd = await getLspCommand();
  const serverCommand = lspCmd.command;
  const serverArgs = lspCmd.args;
  const serverEnv = lspCmd.env;

  if (!serverCommand) {
    window.showErrorMessage(
      "Failed to start Ziex Language Server: zx executable or build step not found."
    );
    return;
  }

  const serverOptions: ServerOptions = {
    command: serverCommand,
    args: serverArgs,
    options: serverEnv ? { env: { ...process.env, ...serverEnv } } : undefined,
  };
  const outputChannel = window.createOutputChannel("Ziex Language Server", {
    log: true,
  });

  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: "file", language: "zx" },
    ],
    traceOutputChannel: outputChannel,
    outputChannel,
  };

  client = new LanguageClient(
    "zx-language-server",
    "Ziex Language Server",
    serverOptions,
    clientOptions,
  );
  client.start();
  activateMultilineStringDecorator(context);
}

type LspCommand = {
  command: string;
  args: string[];
  env?: Record<string, string>;
};

async function getLspCommand(): Promise<LspCommand> {
  const cwd = workspace.workspaceFolders?.[0]?.uri.fsPath;

  // Prefer installed `zx lsp`. Only then resolve ZX_MODULE_PATH via
  // `zig build zx -- env` so we can pass --zx-module.
  try {
    await execFile("zx", ["version"], {
      cwd,
      maxBuffer: 1024 * 1024,
      timeout: 5000,
    });
    const zxModulePath = cwd
      ? (await readZxModulePath(cwd)) ?? undefined
      : undefined;
    const args = ["lsp"];
    if (zxModulePath) {
      args.push("--zx-module", zxModulePath);
    }
    return {
      command: "zx",
      args,
      env: zxModulePath ? { ZX_MODULE_PATH: zxModulePath } : undefined,
    };
  } catch {
    if (cwd && (await hasZxBuildStep(cwd))) {
      return {
        command: "zig",
        args: ["build", "zx", "-Dziex-lsp=true", "--release=fast", "--", "lsp"],
      };
    }
    return { command: "", args: [] };
  }
}

async function readZxModulePath(cwd: string): Promise<string | undefined> {
  if (!(await hasZxBuildStep(cwd))) return undefined;
  try {
    const { stdout } = await execFile(
      "zig",
      ["build", "zx", "--", "env", "--fmt=json"],
      {
        cwd,
        maxBuffer: 1024 * 1024,
        timeout: 60_000,
      },
    );
    const jsonStart = stdout.indexOf("{");
    const jsonEnd = stdout.lastIndexOf("}");
    if (jsonStart < 0 || jsonEnd < jsonStart) return undefined;
    const parsed = JSON.parse(stdout.slice(jsonStart, jsonEnd + 1)) as {
      zx_module_path?: string | null;
    };
    return parsed.zx_module_path ?? undefined;
  } catch (error: any) {
    // @ts-ignore
    console.error("failed to read zx env", error);
    return undefined;
  }
}

interface BuildStep {
  name: string;
  description: string;
}

function parseBuildSteps(output: string): BuildStep[] {
  const steps: BuildStep[] = [];
  const lines = output.split("\n");

  for (const line of lines) {
    if (!line.trim()) continue;
    const trimmed = line.trimStart();

    const parts = trimmed.split(/\s{2,}/);
    if (parts.length >= 2) {
      const namePart = parts[0].replace(/\s*\([^)]+\)\s*$/, "").trim();
      const description = parts.slice(1).join(" ").trim();
      if (namePart && description) {
        steps.push({ name: namePart, description });
      }
    }
  }

  return steps;
}

async function hasZxBuildStep(cwd: string): Promise<boolean> {
  try {
    const { stdout } = await execFile("zig", ["build", "-l"], {
      cwd,
      maxBuffer: 1024 * 1024,
      timeout: 5000,
    });
    const steps = parseBuildSteps(stdout);
    return steps.some((step) => step.name === "zx");
  } catch (error: any) {
    // @ts-ignore
    console.error(error);
    return false;
  }
}


export async function deactivate(): Promise<void> {
  if (client) await client.stop();
}
