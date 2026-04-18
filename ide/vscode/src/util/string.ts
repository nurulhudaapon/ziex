import * as vscode from "vscode";

/**
 * Multiline string literal helpers for Zig/ZX:
 *
 * • Visual:     Fades `\\` prefixes and highlights blocks with a left border
 * • Enter:      Auto-continues `\\` on newline (via onEnterRules)
 * • Toggle:     Adds/removes `\\` from selected lines  (Alt+M)
 * • Paste:      Auto-prefixes pasted text inside a `\\` block
 * • Backspace:  Removes whole `\\` prefix when cursor is right after it
 * • Folding:    Collapses consecutive `\\` lines into one
 */

// -- Regex -- //
const MULTILINE_PREFIX_RE = /^(\s*)(\\\\)/gm;
const MULTILINE_LINE_RE = /^(\s*)\\\\/;

// -- Decoration types -- //
let backslashDecoration: vscode.TextEditorDecorationType;
let blockBorderDecoration: vscode.TextEditorDecorationType;

// -- Activation -- //
export function activateMultilineStringDecorator(
  context: vscode.ExtensionContext,
) {
  // Fade the \\ markers
  backslashDecoration = vscode.window.createTextEditorDecorationType({
    opacity: "0.35",
    letterSpacing: "-0.1em",
    color: new vscode.ThemeColor("editorLineNumber.foreground"),
  });

  // Border where string column starts
  blockBorderDecoration = vscode.window.createTextEditorDecorationType({
    before: {
      contentText: "",
      width: "0px",
      height: "100%",
      border: "1px solid",
      color: new vscode.ThemeColor("editorLineNumber.foreground"),
      margin: "0 1px 0 0",
      textDecoration: "none; display: inline-block; vertical-align: middle;",
    },
    overviewRulerColor: new vscode.ThemeColor("editorLineNumber.foreground"),
    overviewRulerLane: vscode.OverviewRulerLane.Left,
  });

  const trigger = (editor?: vscode.TextEditor) => {
    if (editor) updateDecorations(editor);
  };

  if (vscode.window.activeTextEditor) trigger(vscode.window.activeTextEditor);

  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor(trigger),
    vscode.workspace.onDidChangeTextDocument((e) => {
      const editor = vscode.window.activeTextEditor;
      if (editor && e.document === editor.document) trigger(editor);
    }),
    backslashDecoration,
    blockBorderDecoration,
  );

  // -- Commands -- //
  context.subscriptions.push(
    vscode.commands.registerCommand(
      "zx.toggleMultilineStringLiteral",
      toggleMultilineStringLiteral,
    ),
    vscode.commands.registerCommand(
      "zx.multilineSmartBackspace",
      multilineSmartBackspace,
    ),
  );

  // -- Copy command - strip \\ prefixes when copying from multiline string -- //
  context.subscriptions.push(
    vscode.commands.registerCommand(
      "zx.copyFromMultilineString",
      copyFromMultilineString,
    ),
  );

  // -- Paste command - auto-prefix pasted text with \\ -- //
  context.subscriptions.push(
    vscode.commands.registerCommand(
      "zx.pasteInMultilineString",
      pasteInMultilineString,
    ),
  );

  // -- Folding provider - collapse multiline string blocks -- //
  context.subscriptions.push(
    vscode.languages.registerFoldingRangeProvider(
      [{ language: "zx" }, { language: "zig" }],
      { provideFoldingRanges: provideMlsFoldingRanges },
    ),
  );
}

// -- Decorations -- //
function updateDecorations(editor: vscode.TextEditor) {
  const { document } = editor;
  if (document.languageId !== "zx" && document.languageId !== "zig") return;

  const text = document.getText();
  const backslashRanges: vscode.DecorationOptions[] = [];
  const borderRanges: vscode.DecorationOptions[] = [];

  MULTILINE_PREFIX_RE.lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = MULTILINE_PREFIX_RE.exec(text)) !== null) {
    const bsStart = match.index + match[1].length;
    const bsEnd = bsStart + match[2].length;

    const startPos = document.positionAt(bsStart);
    const endPos = document.positionAt(bsEnd);

    backslashRanges.push({ range: new vscode.Range(startPos, endPos) });
    // Place the vertical bar pseudo-element right after \\
    borderRanges.push({
      range: new vscode.Range(endPos, endPos),
    });
  }

  editor.setDecorations(backslashDecoration, backslashRanges);
  editor.setDecorations(blockBorderDecoration, borderRanges);
}

// -- Toggle multiline string literal --//
async function toggleMultilineStringLiteral() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;

  const { document, selection } = editor;
  if (document.languageId !== "zx" && document.languageId !== "zig") return;

  let newText = "";
  let range = new vscode.Range(selection.start, selection.end);

  const firstLine = document.lineAt(selection.start.line);
  const nonWhitespaceIndex = firstLine.firstNonWhitespaceCharacterIndex;

  for (
    let lineNum = selection.start.line;
    lineNum <= selection.end.line;
    lineNum++
  ) {
    const line = document.lineAt(lineNum);
    const trimmedStart = line.text.slice(line.firstNonWhitespaceCharacterIndex);
    const isMLSL = trimmedStart.startsWith("\\\\");

    const bp = Math.min(
      nonWhitespaceIndex,
      line.firstNonWhitespaceCharacterIndex,
    );

    let newLine: string;
    if (isMLSL) {
      // Remove the \\ prefix
      newLine =
        line.text.slice(0, line.firstNonWhitespaceCharacterIndex) +
        line.text.slice(line.firstNonWhitespaceCharacterIndex + 2);
    } else if (line.isEmptyOrWhitespace) {
      newLine = " ".repeat(nonWhitespaceIndex) + "\\\\";
    } else {
      newLine = line.text.slice(0, bp) + "\\\\" + line.text.slice(bp);
    }

    newText += newLine;
    if (lineNum < selection.end.line) newText += "\n";
    range = range.union(line.range);
  }

  await editor.edit((builder) => {
    builder.replace(range, newText);
  });
}

// -- Smart Backspace --//
// When cursor is right after \\, delete the whole \\ prefix instead of one char.
async function multilineSmartBackspace() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;

  const { document, selection } = editor;
  if (document.languageId !== "zx" && document.languageId !== "zig") {
    await vscode.commands.executeCommand("deleteLeft");
    return;
  }

  const pos = selection.active;
  const lineText = document.lineAt(pos.line).text;
  const m = lineText.match(MULTILINE_LINE_RE);

  // Check if cursor is right after the \\ (at indent + 2)
  if (m && pos.character === m[1].length + 2 && selection.isEmpty) {
    // Delete the \\ and join with previous line
    const prevLineEnd =
      pos.line > 0
        ? document.lineAt(pos.line - 1).range.end
        : new vscode.Position(0, 0);
    const afterBackslash = lineText.slice(m[1].length + 2);

    if (afterBackslash.trim().length === 0 && pos.line > 0) {
      // Line only has \\ (+ whitespace) → delete the entire line
      const deleteRange = new vscode.Range(
        prevLineEnd,
        document.lineAt(pos.line).range.end,
      );
      await editor.edit((edit) => edit.delete(deleteRange));
    } else {
      // Line has content after \\ → just remove the \\
      const bsRange = new vscode.Range(
        pos.line,
        m[1].length,
        pos.line,
        m[1].length + 2,
      );
      await editor.edit((edit) => edit.delete(bsRange));
    }
  } else {
    await vscode.commands.executeCommand("deleteLeft");
  }
}

// ─── Copy from multiline string ────────────────────────────────────────
// Strips \\ prefixes from copied text so it pastes cleanly outside
// multiline string blocks.  Falls through to built-in copy otherwise.
async function copyFromMultilineString() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    await vscode.commands.executeCommand("editor.action.clipboardCopyAction");
    return;
  }

  const { document, selection } = editor;
  if (document.languageId !== "zx" && document.languageId !== "zig") {
    await vscode.commands.executeCommand("editor.action.clipboardCopyAction");
    return;
  }

  // Check if ALL selected lines are multiline-string lines
  let allMLS = true;
  for (
    let lineNum = selection.start.line;
    lineNum <= selection.end.line;
    lineNum++
  ) {
    const lineText = document.lineAt(lineNum).text;
    // Skip the last line if selection ends at column 0 (no content selected)
    if (lineNum === selection.end.line && selection.end.character === 0)
      continue;
    if (!MULTILINE_LINE_RE.test(lineText)) {
      allMLS = false;
      break;
    }
  }

  if (!allMLS || selection.isEmpty) {
    await vscode.commands.executeCommand("editor.action.clipboardCopyAction");
    return;
  }

  // Get the selected text and strip \\ prefixes
  const selectedText = document.getText(selection);
  const stripped = selectedText
    .split("\n")
    .map((line) => {
      const m = line.match(MULTILINE_LINE_RE);
      return m ? line.slice(m[1].length + 2) : line;
    })
    .join("\n");

  await vscode.env.clipboard.writeText(stripped);
}

// ─── Paste inside multiline string ─────────────────────────────────────
// Reads clipboard, prefixes each line with \\, then inserts.
// Only activates when the cursor is on a \\ line; otherwise falls through
// to the built-in paste.

async function pasteInMultilineString() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    await vscode.commands.executeCommand("editor.action.clipboardPasteAction");
    return;
  }

  const { document } = editor;
  if (document.languageId !== "zx" && document.languageId !== "zig") {
    await vscode.commands.executeCommand("editor.action.clipboardPasteAction");
    return;
  }

  const pos = editor.selection.active;
  const lineText = document.lineAt(pos.line).text;
  const m = lineText.match(MULTILINE_LINE_RE);

  if (!m) {
    // Not on a multiline-string line → default paste
    await vscode.commands.executeCommand("editor.action.clipboardPasteAction");
    return;
  }

  const clipboard = await vscode.env.clipboard.readText();
  if (!clipboard || !clipboard.includes("\n")) {
    // Single-line paste → default paste
    await vscode.commands.executeCommand("editor.action.clipboardPasteAction");
    return;
  }

  const indent = m[1];
  const lines = clipboard.split("\n");

  // If every non-first line is already prefixed with \\, don't double-prefix
  const alreadyPrefixed = lines
    .slice(1)
    .every((l) => l.trimStart().startsWith("\\\\") || l.trim() === "");

  const prefixed = alreadyPrefixed
    ? clipboard
    : lines.map((l, i) => (i === 0 ? l : indent + "\\\\" + l)).join("\n");

  // Replace selection (or insert at cursor) with the prefixed text
  await editor.edit((edit) => {
    if (editor.selection.isEmpty) {
      edit.insert(editor.selection.active, prefixed);
    } else {
      edit.replace(editor.selection, prefixed);
    }
  });
}

// -- Folding --//
// Groups consecutive \\ lines into foldable regions.
function provideMlsFoldingRanges(
  document: vscode.TextDocument,
): vscode.FoldingRange[] {
  const ranges: vscode.FoldingRange[] = [];
  let blockStart: number | null = null;

  for (let i = 0; i < document.lineCount; i++) {
    const isML = MULTILINE_LINE_RE.test(document.lineAt(i).text);

    if (isML && blockStart === null) {
      blockStart = i;
    } else if (!isML && blockStart !== null) {
      // Block ended on previous line
      if (i - 1 > blockStart) {
        ranges.push(
          new vscode.FoldingRange(
            blockStart,
            i - 1,
            vscode.FoldingRangeKind.Region,
          ),
        );
      }
      blockStart = null;
    }
  }

  // Close trailing block
  if (blockStart !== null && document.lineCount - 1 > blockStart) {
    ranges.push(
      new vscode.FoldingRange(
        blockStart,
        document.lineCount - 1,
        vscode.FoldingRangeKind.Region,
      ),
    );
  }

  return ranges;
}
