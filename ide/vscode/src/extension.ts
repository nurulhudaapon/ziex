import * as childProcess from "child_process";
import * as util from "util";
import { ExtensionContext, window, workspace } from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions
} from "vscode-languageclient/node";

import { registerHtmlAutoCompletion } from "./util/html";
import { activateMultilineStringDecorator } from "./util/string";

let client: LanguageClient;
const execFile = util.promisify(childProcess.execFile);

export async function activate(context: ExtensionContext) {
  const lspCmd = await getLspCommand();
  const serverCommand = lspCmd.command;
  const serverArgs = lspCmd.args;

  if (!serverCommand) {
    window.showErrorMessage(
      "Failed to start Ziex Language Server: zx executable or build step not found."
    );
    return;
  }

  const serverOptions: ServerOptions = { command: serverCommand, args: serverArgs };
  const outputChannel = window.createOutputChannel("Ziex Language Server", {
    log: true,
  });

  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: "file", language: "zx" },
    ],
    traceOutputChannel: outputChannel,
    outputChannel,
    initializationOptions: {
      inlayHints: {
        enabled: false,
      },
    },
    middleware: {
      provideInlayHints: () => {
        return [];
      },
    },
  };

  client = new LanguageClient(
    "zx-language-server",
    "Ziex Language Server",
    serverOptions,
    clientOptions,
  );
  client.start();
  registerHtmlAutoCompletion(context, "zx");
  activateMultilineStringDecorator(context);
}

async function getLspCommand(): Promise<{ command: string; args: string[] }> {
  const cwd = workspace.workspaceFolders?.[0]?.uri.fsPath;

  // Try zx lsp first
  try {
    await execFile("zx", ["version"], {
      cwd,
      maxBuffer: 1024 * 1024,
      timeout: 5000,
    });
    return { command: "zx", args: ["lsp"] };
  } catch {
    // Fallback to zig build zx -- lsp if available
    if (cwd && (await hasZxBuildStep(cwd))) {
      return { command: "zig", args: ["build", "zx", "--", "lsp"] };
    }
    return { command: "", args: [] };
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
    console.error(error);
    return false;
  }
}


export async function deactivate(): Promise<void> {
  if (client) await client.stop();
}
