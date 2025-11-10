import * as vscode from "vscode";
import { ExtensionContext, window, workspace } from "vscode";

import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from "vscode-languageclient/node";

import { getZLSPath } from "./util";

import { formatZx, preCompileZigFmt } from "./fmt/fmt";

let client: LanguageClient;

export function activate(context: ExtensionContext) {
  const serverCommand = getZLSPath(context);

  if (!serverCommand) {
    window.showErrorMessage(
      "Failed to start ZX Language Server: ZLS not found",
    );
    return;
  }

  // Warm up zig fmt process to avoid JIT compilation delay on first format
  preCompileZigFmt();

  const serverOptions: ServerOptions = {
    command: serverCommand,
  };

  const outputChannel = window.createOutputChannel("ZX Language Server", {
    log: true,
  });

  // Options to control the language client
  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "zx" }],
    traceOutputChannel: outputChannel,
    outputChannel,
    middleware: {
      async provideDocumentFormattingEdits(document, options, token, next) {
        const enableZigExpression = vscode.workspace
          .getConfiguration("zx")
          .get<boolean>("format.enableZigExpression", false);

        const result = provideFormattingEdits(document, options, token);
        return result;
      },
      handleDiagnostics(uri, diagnostics, next) {
        const filteredDiagnostics = diagnostics.map((diag) => {
          // Filter out diagnostics with code "ZigE0424" (unused variable)
          if (
            diag.severity === vscode.DiagnosticSeverity.Error &&
            diag.message === "expected expression, found '<'"
          ) {
            diag.severity = vscode.DiagnosticSeverity.Hint;
            diag.message =
              "ZX syntax: minimal LSP support will be available for now";
          }
          return diag;
        });
        next(uri, filteredDiagnostics);
      },
    },
  };

  client = new LanguageClient(
    "zx-language-server",
    "ZX Language Server",
    serverOptions,
    clientOptions,
  );

  // Register virtual document providers
  const virtualZigDocumentContents = new Map<string, string>();
  const virtualHtmlDocumentContents = new Map<string, string>();

  // Virtual document provider for Zig content
  context.subscriptions.push(
    workspace.registerTextDocumentContentProvider("embedded-content-fmt-zig", {
      provideTextDocumentContent: (uri) => {
        const originalUri = uri.path.slice(1).slice(0, -4); // Remove leading '/' and '.zig'
        const decodedUri = decodeURIComponent(originalUri);
        return virtualZigDocumentContents.get(decodedUri);
      },
    }),
  );

  // Virtual document provider for HTML content
  context.subscriptions.push(
    workspace.registerTextDocumentContentProvider("embedded-content-fmt-html", {
      provideTextDocumentContent: (uri) => {
        const originalUri = uri.path.slice(1).slice(0, -5); // Remove leading '/' and '.html'
        const decodedUri = decodeURIComponent(originalUri);
        return virtualHtmlDocumentContents.get(decodedUri);
      },
    }),
  );

  // Helper function to format using virtual documents
  async function provideFormattingEdits(
    document: vscode.TextDocument,
    options: vscode.FormattingOptions,
    token: vscode.CancellationToken,
  ): Promise<vscode.TextEdit[] | null> {
    const documentText = document.getText();
    const originalUri = document.uri.toString(true);

    // Use the high-level formatZx function to format the entire document
    const result = await formatZx(
      documentText,
      token,
      originalUri,
      virtualHtmlDocumentContents,
    );

    // Return the complete replacement edit
    const lastLineId = document.lineCount - 1;
    const wholeDocument = new vscode.Range(
      0,
      0,
      lastLineId,
      document.lineAt(lastLineId).text.length,
    );
    return [new vscode.TextEdit(wholeDocument, result)];
  }

  // Start the client. This will also launch the server
  client.start();

  // Register command to toggle embedded Zig expression formatting
  context.subscriptions.push(
    vscode.commands.registerCommand(
      "zx.toggleZigExpressionFormatting",
      async () => {
        const config = workspace.getConfiguration("zx");
        const current = config.get<boolean>("format.enableZigExpression", true);
        const newValue = !current;
        await config.update(
          "format.enableZigExpression",
          newValue,
          vscode.ConfigurationTarget.Global,
        );
        vscode.window.showInformationMessage(
          `ZX: embedded Zig expression formatting is now ${
            newValue ? "enabled" : "disabled"
          }`,
        );
      },
    ),
  );
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  return client.stop();
}
