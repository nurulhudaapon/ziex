import * as fs from "fs";
import * as path from "path";
import { ExtensionContext, extensions, window } from "vscode";

export function getZLSPath(context: ExtensionContext): string | undefined {
  // Try to get the Zig extension
  const zigExtension = extensions.getExtension("ziglang.vscode-zig");

  if (!zigExtension) {
    window.showErrorMessage(
      "Zig extension not found. Please install the official Zig Language extension.",
    );
    return undefined;
  }

  // The Zig extension stores ZLS in its global storage path
  // Typical path structure: <globalStoragePath>/zls_install/<version>/zls
  const zigGlobalStoragePath = context.globalStorageUri.fsPath.replace(
    path.basename(context.globalStorageUri.fsPath),
    "ziglang.vscode-zig",
  );

  // Check for zls in the standard location
  const zlsInstallPath = path.join(zigGlobalStoragePath, "zls");

  if (fs.existsSync(zlsInstallPath)) {
    // Find the version directory (usually there's only one)
    const versions = fs.readdirSync(zlsInstallPath);

    for (const version of versions) {
      const zlsPath = path.join(zlsInstallPath, version, "zls");
      const zlsPathExe = path.join(zlsInstallPath, version, "zls.exe"); // Windows

      if (fs.existsSync(zlsPath)) {
        return zlsPath;
      } else if (fs.existsSync(zlsPathExe)) {
        return zlsPathExe;
      }
    }
  }

  window.showErrorMessage(
    "ZLS binary not found in Zig extension storage. Please ensure ZLS is installed via the Zig extension.",
  );
  return undefined;
}
