import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";

export const ZX_VIRTUAL_SCHEME = "zx-zig";
const ZX_CACHE_DIR = ".zig-cache/tmp/.zx/transpiled";

const createdTranspiledFiles = new Set<string>();
const zxToZigPathMap = new Map<string, string>();
const documentOffsetMaps = new Map<string, LineOffsetMap>();

let virtualDocProvider: ZxVirtualDocumentProvider | null = null;

function getTranspiledDir(workspaceRoot: string): string {
  return path.join(workspaceRoot, ZX_CACHE_DIR);
}

function getTranspiledPath(zxPath: string, workspaceRoot: string): string {
  const relativePath = path.relative(workspaceRoot, zxPath);
  const zigRelativePath = relativePath.replace(/\.zx$/, ".zig");
  return path.join(getTranspiledDir(workspaceRoot), zigRelativePath);
}

export function getOriginalZxPath(zigPath: string, workspaceRoot: string): string | null {
  const transpiledDir = getTranspiledDir(workspaceRoot);
  if (!zigPath.startsWith(transpiledDir)) return null;
  const relativePath = path.relative(transpiledDir, zigPath);
  const zxRelativePath = relativePath.replace(/\.zig$/, ".zx");
  return path.join(workspaceRoot, zxRelativePath);
}

export function isTranspiledPath(filePath: string, workspaceRoot: string): boolean {
  return filePath.startsWith(getTranspiledDir(workspaceRoot));
}

export function transformZxImportsToZig(content: string): string {
  return content.replace(/\.zx"/g, '.zig"');
}

export function transformZigImportsToZx(content: string): string {
  return content.replace(/\.zig"/g, '.zx"');
}

export interface LineOffsetMap {
  lineOffsets: Map<number, Array<{ column: number; cumulativeOffset: number }>>;
}

export function createLineOffsetMap(originalContent: string): LineOffsetMap {
  const lineOffsets = new Map<number, Array<{ column: number; cumulativeOffset: number }>>();
  const lines = originalContent.split("\n");
  let cumulativeOffset = 0;

  for (let lineNum = 0; lineNum < lines.length; lineNum++) {
    const line = lines[lineNum];
    const regex = /\.zx"/g;
    let match;
    const lineData: Array<{ column: number; cumulativeOffset: number }> = [];

    while ((match = regex.exec(line)) !== null) {
      cumulativeOffset += 1;
      lineData.push({ column: match.index + 3, cumulativeOffset });
    }

    if (lineData.length > 0) {
      lineOffsets.set(lineNum, lineData);
    }
  }

  return { lineOffsets };
}

export function adjustColumnToOriginal(
  line: number,
  transformedColumn: number,
  offsetMap: LineOffsetMap
): { column: number; newGlobalOffset: number } {
  let globalOffset = 0;
  for (let i = 0; i < line; i++) {
    const lineData = offsetMap.lineOffsets.get(i);
    if (lineData && lineData.length > 0) {
      globalOffset = lineData[lineData.length - 1].cumulativeOffset;
    }
  }

  const lineData = offsetMap.lineOffsets.get(line);
  if (!lineData) {
    return { column: transformedColumn, newGlobalOffset: globalOffset };
  }

  let lineOffset = 0;
  for (const { column: origCol, cumulativeOffset } of lineData) {
    const transformedPos = origCol + (cumulativeOffset - globalOffset);
    if (transformedPos <= transformedColumn) {
      lineOffset = cumulativeOffset - globalOffset;
    } else {
      break;
    }
  }

  return {
    column: transformedColumn - lineOffset,
    newGlobalOffset: globalOffset + lineOffset,
  };
}

export function getOffsetMap(uri: string, content: string): LineOffsetMap {
  const map = createLineOffsetMap(content);
  documentOffsetMaps.set(uri, map);
  return map;
}

export function clearOffsetMap(uri: string): void {
  documentOffsetMaps.delete(uri);
}

export function adjustSemanticTokens(data: number[], offsetMap: LineOffsetMap): number[] {
  const adjusted = [...data];
  let currentLine = 0;
  let prevLineOffset = 0;

  for (let i = 0; i < adjusted.length; i += 5) {
    const deltaLine = adjusted[i];
    const deltaStartChar = adjusted[i + 1];

    currentLine += deltaLine;

    let absoluteStartChar: number;
    if (deltaLine > 0) {
      absoluteStartChar = deltaStartChar;
      prevLineOffset = 0;
    } else {
      absoluteStartChar = prevLineOffset + deltaStartChar;
    }

    const { column: adjustedColumn } = adjustColumnToOriginal(currentLine, absoluteStartChar, offsetMap);

    if (deltaLine > 0) {
      adjusted[i + 1] = adjustedColumn;
    } else {
      adjusted[i + 1] = deltaStartChar - (absoluteStartChar - adjustedColumn);
    }

    prevLineOffset = absoluteStartChar;
  }

  return adjusted;
}

function createTranspiledFile(zxPath: string, workspaceRoot: string): string | null {
  const zigPath = getTranspiledPath(zxPath, workspaceRoot);

  try {
    const zigDir = path.dirname(zigPath);
    if (!fs.existsSync(zigDir)) {
      fs.mkdirSync(zigDir, { recursive: true });
    }

    const content = fs.readFileSync(zxPath, "utf-8");
    const transformedContent = transformZxImportsToZig(content);
    fs.writeFileSync(zigPath, transformedContent);

    createdTranspiledFiles.add(zigPath);
    zxToZigPathMap.set(zxPath, zigPath);

    return zigPath;
  } catch (e) {
    console.error(`ZX: Could not create transpiled file for ${zxPath}:`, e);
    return null;
  }
}

function removeTranspiledFile(zxPath: string, workspaceRoot: string): void {
  const zigPath = getTranspiledPath(zxPath, workspaceRoot);

  try {
    if (fs.existsSync(zigPath)) {
      fs.unlinkSync(zigPath);
    }
    createdTranspiledFiles.delete(zigPath);
    zxToZigPathMap.delete(zxPath);
  } catch {
    // Ignore
  }
}

export class ZxVirtualDocumentProvider implements vscode.TextDocumentContentProvider {
  private _onDidChange = new vscode.EventEmitter<vscode.Uri>();
  readonly onDidChange = this._onDidChange.event;
  private workspaceRoot: string;

  constructor(workspaceRoot: string) {
    this.workspaceRoot = workspaceRoot;
  }

  provideTextDocumentContent(uri: vscode.Uri): string | null {
    const zigPath = uri.fsPath;

    if (fs.existsSync(zigPath)) {
      return fs.readFileSync(zigPath, "utf-8");
    }

    const originalZxPath = getOriginalZxPath(zigPath, this.workspaceRoot);
    if (originalZxPath && fs.existsSync(originalZxPath)) {
      createTranspiledFile(originalZxPath, this.workspaceRoot);
      if (fs.existsSync(zigPath)) {
        return fs.readFileSync(zigPath, "utf-8");
      }
    }

    return null;
  }

  refresh(zxUri: vscode.Uri): void {
    const zxPath = zxUri.fsPath;
    createTranspiledFile(zxPath, this.workspaceRoot);

    const zigPath = getTranspiledPath(zxPath, this.workspaceRoot);
    const virtualUri = vscode.Uri.from({ scheme: ZX_VIRTUAL_SCHEME, path: zigPath });
    this._onDidChange.fire(virtualUri);
  }
}

export function createUriConverters(workspaceRoot: string) {
  return {
    code2Protocol: (uri: vscode.Uri): string => {
      if (uri.scheme === ZX_VIRTUAL_SCHEME) {
        return vscode.Uri.file(uri.path).toString();
      }
      if (uri.fsPath.endsWith(".zx")) {
        const zigPath = getTranspiledPath(uri.fsPath, workspaceRoot);
        return vscode.Uri.file(zigPath).toString();
      }
      return uri.toString();
    },

    protocol2Code: (uriString: string): vscode.Uri => {
      const uri = vscode.Uri.parse(uriString);
      if (uri.scheme === "file" && uri.fsPath.includes(ZX_CACHE_DIR)) {
        return vscode.Uri.from({ scheme: ZX_VIRTUAL_SCHEME, path: uri.fsPath });
      }
      return uri;
    },
  };
}

export function getVirtualDocumentProvider(workspaceRoot: string): ZxVirtualDocumentProvider {
  if (!virtualDocProvider) {
    virtualDocProvider = new ZxVirtualDocumentProvider(workspaceRoot);
  }
  return virtualDocProvider;
}

async function syncAllZxFiles(workspaceRoot: string): Promise<void> {
  const files = await vscode.workspace.findFiles("**/*.zx", "**/node_modules/**");
  for (const file of files) {
    createTranspiledFile(file.fsPath, workspaceRoot);
  }
}

function cleanupTranspiledDir(workspaceRoot: string): void {
  const transpiledDir = getTranspiledDir(workspaceRoot);
  try {
    if (fs.existsSync(transpiledDir)) {
      fs.rmSync(transpiledDir, { recursive: true, force: true });
    }
  } catch {
    // Ignore
  }
}

function getWorkspaceRoot(): string | null {
  return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || null;
}

export function registerZxFileProviders(context: vscode.ExtensionContext): void {
  const workspaceRoot = getWorkspaceRoot();
  if (!workspaceRoot) return;

  const provider = getVirtualDocumentProvider(workspaceRoot);

  context.subscriptions.push(
    vscode.workspace.registerTextDocumentContentProvider(ZX_VIRTUAL_SCHEME, provider)
  );

  const watcher = vscode.workspace.createFileSystemWatcher("**/*.zx");

  watcher.onDidCreate((uri) => {
    createTranspiledFile(uri.fsPath, workspaceRoot);
    provider.refresh(uri);
  });

  watcher.onDidChange((uri) => {
    createTranspiledFile(uri.fsPath, workspaceRoot);
    provider.refresh(uri);
  });

  watcher.onDidDelete((uri) => {
    removeTranspiledFile(uri.fsPath, workspaceRoot);
  });

  context.subscriptions.push(watcher);

  context.subscriptions.push(
    vscode.workspace.onDidSaveTextDocument((doc) => {
      if (doc.languageId === "zx" || doc.fileName.endsWith(".zx")) {
        createTranspiledFile(doc.fileName, workspaceRoot);
        provider.refresh(doc.uri);
      }
    })
  );

  syncAllZxFiles(workspaceRoot);
}

export async function disposeZxFileProviders(): Promise<void> {
  const workspaceRoot = getWorkspaceRoot();
  if (workspaceRoot) {
    cleanupTranspiledDir(workspaceRoot);
  }

  createdTranspiledFiles.clear();
  zxToZigPathMap.clear();
  virtualDocProvider = null;
}
