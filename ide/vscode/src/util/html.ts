import * as vscode from "vscode";
import {
  getLanguageService,
  TextDocument as HTMLTextDocument,
} from "vscode-html-languageservice";

const htmlService = getLanguageService({});

// ZX Builtin Attributes Documentation
const ZX_BUILTIN_ATTRIBUTES: Record<
  string,
  { description: string; values?: string[] }
> = {
  "@allocator": {
    description: `**@allocator** - Memory Allocator Attribute

The \`@allocator\` attribute is **required** on the topmost component element. All child components automatically inherit the allocator from their parent.

**Why is @allocator needed?**

ZX components allocate memory for:
- Storing text content (which is HTML-escaped and allocated)
- Copying child components arrays
- Copying attribute arrays  
- Formatting expressions that allocate formatted strings

**Usage:**
\`\`\`zx
<div @allocator={ctx.arena}>
    <h1>Hello World</h1>
</div>
\`\`\`

**Best Practices:**
- Always use \`ctx.arena\` in page components (auto-freed after request)
- Pass allocator parameter to custom components
- Set \`@allocator\` on the root element of each component that needs memory allocation
- Child components inherit the allocator from their parent`,
    values: ["ctx.arena", "allocator", "ctx.allocator"],
  },
  "@rendering": {
    description: `**@rendering** - Client-Side Rendering Mode

The \`@rendering\` attribute controls how a component is rendered on the client side. Used to enable client-side interactivity for components.

**Values:**
- \`.react\` (Client Side React) - Component is a React component rendered client-side
- \`.client\` (Client Side Zig) - Component is a Zig WASM component rendered client-side

**Usage:**
\`\`\`zx
// React component (CSR)
<CounterComponent @rendering={.react} max_count={10} />

// Zig WASM component (Client)  
<TodoApp @rendering={.client} />
\`\`\`

**Notes:**
- CSR components should have a corresponding \`.tsx\` file with a default export
- Client components are compiled to WebAssembly for client-side execution`,
    values: [".react", ".client"],
  },
  "@escaping": {
    description: `**@escaping** - Content Escaping Mode

The \`@escaping\` attribute controls how content is escaped for HTML safety.

**Values:**
- \`.none\` - Disables HTML escaping, allowing raw HTML/script content

**Usage:**
\`\`\`zx
<script type="module" @escaping={.none}>
    // JavaScript code here is not escaped
    const data = { name: "test" };
</script>
\`\`\`

**Warning:** Use \`.none\` only for trusted content like inline scripts. Never use with user-generated content to prevent XSS attacks.`,
    values: [".none"],
  },
};

export function registerHtmlAutoCompletion(
  ctx: vscode.ExtensionContext | vscode.Disposable,
  languageId: string,
) {
  let applying = false;

  const isInsideReturn = (doc: vscode.TextDocument, pos: vscode.Position) => {
    const txt = doc.getText();
    const offset = doc.offsetAt(pos);
    const before = txt.slice(0, offset);
    const retIdx = before.lastIndexOf("return");
    if (retIdx === -1) return false;
    const afterRetChar = txt[retIdx + 6] || "";
    if (/[\w$]/.test(afterRetChar)) return false;
    const afterReturn = txt.slice(retIdx);
    const openRel = afterReturn.indexOf("(");
    if (openRel === -1) return false;
    const absOpen = retIdx + openRel;
    if (absOpen > offset) return false;
    let depth = 0;
    for (let i = absOpen; i < txt.length; i++) {
      const ch = txt[i];
      if (ch === "(") depth++;
      else if (ch === ")") {
        depth--;
        if (depth === 0) return offset <= i;
      }
    }
    return true;
  };

  // Check if cursor is in an attribute position (inside a tag, after tag name)
  const isInAttributePosition = (
    doc: vscode.TextDocument,
    pos: vscode.Position,
  ) => {
    const line = doc.lineAt(pos.line).text;
    const beforeCursor = line.substring(0, pos.character);
    // Look for an unclosed < tag (we're inside a tag)
    const lastOpenTag = beforeCursor.lastIndexOf("<");
    const lastCloseTag = beforeCursor.lastIndexOf(">");
    if (lastOpenTag > lastCloseTag) {
      // We're inside a tag - check if we're after the tag name
      const tagContent = beforeCursor.substring(lastOpenTag);
      // Match: <tagName followed by space or attributes
      return /^<[a-zA-Z_][a-zA-Z0-9_]*\s/.test(tagContent);
    }
    return false;
  };

  const complete = async (doc: vscode.TextDocument, pos: vscode.Position) => {
    if (!isInsideReturn(doc, pos)) return null;

    const completionItems: vscode.CompletionItem[] = [];

    // Add ZX builtin attributes if in attribute position
    if (isInAttributePosition(doc, pos)) {
      // Check if we already have @ typed (to avoid @@allocator)
      const line = doc.lineAt(pos.line).text;
      const charBefore = pos.character > 0 ? line[pos.character - 1] : "";
      const hasAtPrefix = charBefore === "@";

      for (const [attrName, attrDoc] of Object.entries(ZX_BUILTIN_ATTRIBUTES)) {
        const attrNameWithoutAt = attrName.slice(1); // Remove @ prefix
        const item = new vscode.CompletionItem(
          attrName,
          vscode.CompletionItemKind.Property,
        );
        // If @ is already typed, only insert the rest
        item.insertText = new vscode.SnippetString(
          hasAtPrefix ? `${attrNameWithoutAt}={$1}` : `${attrName}={$1}`,
        );
        item.filterText = attrName;
        item.detail = "ZX Builtin Attribute";
        item.documentation = new vscode.MarkdownString(attrDoc.description);
        item.sortText = "0" + attrName; // Sort builtin attributes first
        completionItems.push(item);

        // Also add value completions for each builtin attribute
        if (attrDoc.values) {
          for (const value of attrDoc.values) {
            const valueItem = new vscode.CompletionItem(
              `${attrName}={${value}}`,
              vscode.CompletionItemKind.Value,
            );
            // If @ is already typed, only insert the rest
            valueItem.insertText = hasAtPrefix
              ? `${attrNameWithoutAt}={${value}}`
              : `${attrName}={${value}}`;
            valueItem.filterText = `${attrName}={${value}}`;
            valueItem.detail = `ZX: ${attrName} value`;
            valueItem.documentation = new vscode.MarkdownString(
              `Set \`${attrName}\` to \`${value}\`\n\n${attrDoc.description}`,
            );
            valueItem.sortText = "1" + attrName + value;
            completionItems.push(valueItem);
          }
        }
      }
    }

    // Get HTML completions
    const html = HTMLTextDocument.create(
      doc.uri.toString(),
      "html",
      doc.version,
      doc.getText(),
    );
    const list = htmlService.doComplete(
      html,
      { line: pos.line, character: pos.character },
      htmlService.parseHTMLDocument(html),
    );

    if (list) {
      const htmlItems = (list.items as any[]).map((it: any) => {
        const label = typeof it.label === "string" ? it.label : it.label.label;
        const insert = (() => {
          let t = it.insertText ?? label;
          if (typeof t === "string") t = t.replace(/^</, "");
          const m = typeof t === "string" && t.match(/^([\w:-]+)/);
          return m ? m[1] : t;
        })();
        const item = new vscode.CompletionItem(
          label,
          vscode.CompletionItemKind.Property,
        );
        item.insertText = insert;
        if (it.detail) item.detail = it.detail;
        if (it.documentation)
          item.documentation =
            typeof it.documentation === "string"
              ? it.documentation
              : it.documentation.value;
        item.sortText = "2" + label; // Sort HTML items after builtin attributes
        return item;
      });
      completionItems.push(...htmlItems);
    }

    if (completionItems.length === 0) return null;
    return new vscode.CompletionList(completionItems, false);
  };

  const onType = async (
    doc: vscode.TextDocument,
    pos: vscode.Position,
    ch: string,
  ) => {
    if (doc.languageId !== languageId || ch !== ">") return [];
    if (
      !vscode.workspace
        .getConfiguration("zx")
        .get<boolean>("autoCloseTags", true)
    )
      return [];
    if (!isInsideReturn(doc, pos)) return [];
    const html = HTMLTextDocument.create(
      doc.uri.toString(),
      "html",
      doc.version,
      doc.getText(),
    );
    const insert = htmlService.doTagComplete(
      html,
      { line: pos.line, character: pos.character },
      htmlService.parseHTMLDocument(html),
    );
    if (!insert) return [];
    if (insert.includes("$")) {
      const ed = vscode.window.activeTextEditor;
      if (ed && ed.document.uri.toString() === doc.uri.toString()) {
        applying = true;
        await ed.insertSnippet(new vscode.SnippetString(insert), pos);
        applying = false;
      }
      return [];
    }
    return [vscode.TextEdit.insert(pos, insert)];
  };

  const hover = async (doc: vscode.TextDocument, pos: vscode.Position) => {
    if (!isInsideReturn(doc, pos)) return null;

    // Check for ZX builtin attributes (@allocator, @rendering, @escaping)
    const line = doc.lineAt(pos.line).text;
    const wordRange = doc.getWordRangeAtPosition(pos, /@[a-zA-Z_][a-zA-Z0-9_]*/);
    if (wordRange) {
      const word = doc.getText(wordRange);
      const builtinDoc = ZX_BUILTIN_ATTRIBUTES[word];
      if (builtinDoc) {
        const markdown = new vscode.MarkdownString(builtinDoc.description);
        markdown.isTrusted = true;
        return new vscode.Hover(markdown, wordRange);
      }
    }

    // Check if hovering over a builtin attribute value pattern (e.g., .react, .client, .none)
    const valueRange = doc.getWordRangeAtPosition(pos, /\.[a-zA-Z_][a-zA-Z0-9_]*/);
    if (valueRange) {
      const value = doc.getText(valueRange);
      // Find which builtin attribute this value belongs to by looking backwards on the line
      const lineText = line.substring(0, valueRange.start.character);
      for (const [attrName, attrDoc] of Object.entries(ZX_BUILTIN_ATTRIBUTES)) {
        if (lineText.includes(attrName) && attrDoc.values?.includes(value)) {
          const markdown = new vscode.MarkdownString(
            `**${value}** - Value for \`${attrName}\`\n\n${attrDoc.description}`,
          );
          markdown.isTrusted = true;
          return new vscode.Hover(markdown, valueRange);
        }
      }
    }

    // Fall back to HTML hover
    const html = HTMLTextDocument.create(
      doc.uri.toString(),
      "html",
      doc.version,
      doc.getText(),
    );
    const hoverResult = htmlService.doHover(
      html,
      { line: pos.line, character: pos.character },
      htmlService.parseHTMLDocument(html),
    );
    if (!hoverResult) return null;

    const contents = hoverResult.contents;
    let markdownContent: vscode.MarkdownString;

    if (typeof contents === "string") {
      markdownContent = new vscode.MarkdownString(contents);
    } else if ("kind" in contents) {
      markdownContent = new vscode.MarkdownString(contents.value);
    } else if (Array.isArray(contents)) {
      const text = contents
        .map((c) => (typeof c === "string" ? c : c.value))
        .join("\n\n");
      markdownContent = new vscode.MarkdownString(text);
    } else {
      markdownContent = new vscode.MarkdownString(contents.value);
    }

    let range: vscode.Range | undefined;
    if (hoverResult.range) {
      range = new vscode.Range(
        hoverResult.range.start.line,
        hoverResult.range.start.character,
        hoverResult.range.end.line,
        hoverResult.range.end.character,
      );
    }

    return new vscode.Hover(markdownContent, range);
  };

  const completionProvider: vscode.CompletionItemProvider = {
    provideCompletionItems: (document, position) =>
      complete(document, position),
  };
  const onTypeProvider: vscode.OnTypeFormattingEditProvider = {
    provideOnTypeFormattingEdits: (document, position, ch) =>
      onType(document, position, ch),
  };
  const hoverProvider: vscode.HoverProvider = {
    provideHover: (document, position) => hover(document, position),
  };

  const subs: vscode.Disposable[] = [
    vscode.languages.registerCompletionItemProvider(
      { language: languageId },
      completionProvider,
      "<",
      "@",
    ),
    vscode.languages.registerOnTypeFormattingEditProvider(
      { language: languageId },
      onTypeProvider,
      ">",
    ),
    vscode.languages.registerHoverProvider(
      { language: languageId },
      hoverProvider,
    ),
  ];

  const listener = vscode.workspace.onDidChangeTextDocument(async (e) => {
    if (
      applying ||
      e.document.languageId !== languageId ||
      e.contentChanges.length !== 1
    )
      return;
    const c = e.contentChanges[0];
    if (c.text !== ">") return;
    if (
      !vscode.workspace
        .getConfiguration("zx")
        .get<boolean>("autoCloseTags", true)
    )
      return;
    const pos = new vscode.Position(
      c.range.start.line,
      c.range.start.character + c.text.length,
    );
    if (!isInsideReturn(e.document, pos)) return;
    const html = HTMLTextDocument.create(
      e.document.uri.toString(),
      "html",
      e.document.version,
      e.document.getText(),
    );
    const insert = htmlService.doTagComplete(
      html,
      { line: pos.line, character: pos.character },
      htmlService.parseHTMLDocument(html),
    );
    if (!insert) return;
    const ed = vscode.window.activeTextEditor;
    if (
      insert.includes("$") &&
      ed &&
      ed.document.uri.toString() === e.document.uri.toString()
    ) {
      applying = true;
      await ed.insertSnippet(new vscode.SnippetString(insert), pos);
      applying = false;
      return;
    }
    applying = true;
    const we = new vscode.WorkspaceEdit();
    we.insert(e.document.uri, pos, insert);
    await vscode.workspace.applyEdit(we);
    applying = false;
  });

  subs.push(listener);
  if (ctx && "subscriptions" in ctx)
    subs.forEach((s) => ctx.subscriptions.push(s));
  return subs;
}

export default registerHtmlAutoCompletion;
