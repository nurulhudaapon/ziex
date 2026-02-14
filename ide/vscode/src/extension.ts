import * as childProcess from "child_process";
import * as util from "util";
import * as vscode from "vscode";
import { ExtensionContext, window, workspace } from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from "vscode-languageclient/node";

import { getZLSPath } from "./util/util";
import { registerHtmlAutoCompletion } from "./util/html";
import {
  registerZxFileProviders,
  disposeZxFileProviders,
  createUriConverters,
  ZX_VIRTUAL_SCHEME,
  transformZxImportsToZig,
  getOffsetMap,
  adjustSemanticTokens,
  getOriginalZxPath,
  isTranspiledPath,
} from "./util/file";

let client: LanguageClient;
const execFile = util.promisify(childProcess.execFile);

function remapLocationsToZx(
  result: vscode.Definition | vscode.LocationLink[] | null | undefined,
  workspaceRoot: string
): vscode.Definition | vscode.LocationLink[] | null | undefined {
  if (!result) return result;

  const remapUri = (uri: vscode.Uri): vscode.Uri => {
    if (isTranspiledPath(uri.fsPath, workspaceRoot)) {
      const originalPath = getOriginalZxPath(uri.fsPath, workspaceRoot);
      if (originalPath) return vscode.Uri.file(originalPath);
    }
    return uri;
  };

  const remapLocation = (loc: vscode.Location): vscode.Location =>
    new vscode.Location(remapUri(loc.uri), loc.range);

  const remapLocationLink = (link: vscode.LocationLink): vscode.LocationLink => ({
    ...link,
    targetUri: remapUri(link.targetUri),
  });

  if (Array.isArray(result)) {
    return result.map((item) => {
      if ("targetUri" in item) return remapLocationLink(item as vscode.LocationLink);
      if ("uri" in item) return remapLocation(item as vscode.Location);
      return item;
    });
  } else if ("uri" in result) {
    return remapLocation(result as vscode.Location);
  }

  return result;
}

export function activate(context: ExtensionContext) {
  const serverCommand = getZLSPath(context);

  if (!serverCommand) {
    window.showErrorMessage("Failed to start ZX Language Server: ZLS not found");
    return;
  }

  const serverOptions: ServerOptions = { command: serverCommand };
  const outputChannel = window.createOutputChannel("ZX Language Server", { log: true });
  const workspaceRoot = workspace.workspaceFolders?.[0]?.uri.fsPath || "";

  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: "file", language: "zx" },
      { scheme: "file", language: "zig" },
      { scheme: ZX_VIRTUAL_SCHEME, language: "zig" },
    ],
    traceOutputChannel: outputChannel,
    outputChannel,
    uriConverters: createUriConverters(workspaceRoot),
    middleware: {
      async provideDocumentFormattingEdits(document, _options, token, _next) {
        return formatWithZxCli(document, token);
      },

      async provideHover(uri, position, token, next) {
        return next(uri, position, token);
      },

      async provideDefinition(document, position, token, next) {
        return remapLocationsToZx(await next(document, position, token), workspaceRoot);
      },

      async provideTypeDefinition(document, position, token, next) {
        return remapLocationsToZx(await next(document, position, token), workspaceRoot);
      },

      async provideDeclaration(document, position, token, next) {
        return remapLocationsToZx(await next(document, position, token), workspaceRoot);
      },

      async provideImplementation(document, position, token, next) {
        return remapLocationsToZx(await next(document, position, token), workspaceRoot);
      },

      async provideReferences(document, position, context, token, next) {
        const result = await next(document, position, context, token);
        if (!result) return result;
        return result.map((loc) => {
          if (isTranspiledPath(loc.uri.fsPath, workspaceRoot)) {
            const originalPath = getOriginalZxPath(loc.uri.fsPath, workspaceRoot);
            if (originalPath) return new vscode.Location(vscode.Uri.file(originalPath), loc.range);
          }
          return loc;
        });
      },

      handleDiagnostics(uri, diagnostics, next) {
        const filtered = diagnostics.filter(
          (d) => !(d.severity === vscode.DiagnosticSeverity.Error && d.message === "expected expression, found '<'")
        );
        next(uri, filtered);
      },

      didOpen: async (document, next) => {
        if (document.languageId === "zx" || document.uri.fsPath.endsWith(".zx")) {
          const originalText = document.getText();
          const transformedText = transformZxImportsToZig(originalText);
          getOffsetMap(document.uri.toString(), originalText);

          if (transformedText !== originalText) {
            return next({ ...document, getText: () => transformedText } as any);
          }
        }
        return next(document);
      },

      didChange: async (event, next) => {
        const document = event.document;
        if (document.languageId === "zx" || document.uri.fsPath.endsWith(".zx")) {
          const originalText = document.getText();
          const transformedText = transformZxImportsToZig(originalText);
          getOffsetMap(document.uri.toString(), originalText);

          if (transformedText !== originalText) {
            return next({
              ...event,
              document: { ...document, getText: () => transformedText },
              contentChanges: event.contentChanges.map((c) => ({ ...c, text: transformZxImportsToZig(c.text) })),
            } as any);
          }
        }
        return next(event);
      },

      provideDocumentSemanticTokens: async (document, token, next) => {
        const result = await next(document, token);

        if (result && (document.languageId === "zx" || document.uri.fsPath.endsWith(".zx"))) {
          const originalText = document.getText();
          if (originalText.includes('.zx"')) {
            const offsetMap = getOffsetMap(document.uri.toString(), originalText);
            if ("data" in result && result.data) {
              const adjustedData = adjustSemanticTokens(Array.from(result.data), offsetMap);
              return new vscode.SemanticTokens(new Uint32Array(adjustedData), result.resultId);
            }
          }
        }

        return result;
      },
    },
  };

  client = new LanguageClient("zx-language-server", "ZX Language Server", serverOptions, clientOptions);
  client.start();

  registerHtmlAutoCompletion(context, "zx");
  registerZxFileProviders(context);
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
    return steps.some(step => step.name === "zx");
  } catch (error: any) {
    console.error(error);
    return false;
  }
}

async function showZxInstallationError(): Promise<void> {
  const installCommand =
    process.platform === "win32"
      ? 'powershell -c "irm ziex.dev/install.ps1 | iex"'
      : "curl -fsSL https://ziex.dev/install | bash";

  const selection = await window.showErrorMessage(
    "ZX CLI not found. Please install it to use code formatting.",
    "Install Now",
    "Copy Installation Script"
  );

  if (selection === "Copy Installation Script") {
    await vscode.env.clipboard.writeText(installCommand);
    window.showInformationMessage("Installation command copied to clipboard!");
  } else if (selection === "Install Now") {
    const terminal = window.createTerminal("ZX CLI Installation");
    terminal.sendText(installCommand);
    terminal.show();
  }
}

async function formatWithZxCli(
  document: vscode.TextDocument,
  token: vscode.CancellationToken
): Promise<vscode.TextEdit[] | null> {
  const abortController = new AbortController();
  token.onCancellationRequested(() => abortController.abort());

  const cwd = workspace.workspaceFolders?.[0]?.uri.fsPath;
  const useZigBuild = cwd ? await hasZxBuildStep(cwd) : false;

  const originalText = document.getText();
  
  let command = useZigBuild ? "zig" : "zx";
  let args = useZigBuild ? ["build", "zx", "--", "fmt", "--stdio"] : ["fmt", "--stdio"];
  
  try {
    const promise = execFile(command, args, {
      cwd,
      maxBuffer: 10 * 1024 * 1024,
      signal: abortController.signal,
      timeout: 60000,
    });
    promise.child.stdin?.end(originalText);

    const { stdout } = await promise;
    if (!stdout || stdout === originalText) return null;

    const lastLineId = document.lineCount - 1;
    const wholeDocument = new vscode.Range(0, 0, lastLineId, document.lineAt(lastLineId).text.length);
    return [new vscode.TextEdit(wholeDocument, stdout)];
  } catch (error: any) {
    if (token.isCancellationRequested) return null;

    const message = error?.stderr?.toString()?.trim() || error?.message || String(error);
    const isNotFound = message.includes("not found") || message.includes("ENOENT") || error.code === "ENOENT";

    // If zx CLI not found and we weren't already using zig build, try zig build as fallback
    if (isNotFound && !useZigBuild && cwd) {
      try {
        const fallbackPromise = execFile("zig", ["build", "zx", "--", "fmt", "--stdio"], {
          cwd,
          maxBuffer: 10 * 1024 * 1024,
          signal: abortController.signal,
          timeout: 60000,
        });
        fallbackPromise.child.stdin?.end(originalText);

        const { stdout } = await fallbackPromise;
        if (!stdout || stdout === originalText) return null;

        const lastLineId = document.lineCount - 1;
        const wholeDocument = new vscode.Range(0, 0, lastLineId, document.lineAt(lastLineId).text.length);
        return [new vscode.TextEdit(wholeDocument, stdout)];
      } catch {
        // Both methods failed, show installation error
        await showZxInstallationError();
        return null;
      }
    } else if (isNotFound) {
      // Already tried zig build, show installation error
      await showZxInstallationError();
    } else {
      const commandStr = useZigBuild ? "zig build zx -- fmt" : "zx fmt";
      window.showErrorMessage(`ZX: failed to format using '${commandStr}': ${message}`);
    }

    return null;
  }
}

export async function deactivate(): Promise<void> {
  await disposeZxFileProviders();
  if (client) await client.stop();
}
