# Ziex

A Zig library for building web applications with JSX-like syntax. Write declarative UI components using familiar JSX patterns, transpiled to efficient Zig code.

**📚 [Full Documentation of Ziex →](https://ziex.dev)**

## Contributing

### Project Overview

This is a VS Code extension that provides syntax highlighting, language support, and formatting for Ziex files (`.zx`). ZX allows you to write HTML within Zig code using JSX-like syntax.

#### Project Structure

```
zx-vscode/
├── src/                    # TypeScript source code
│   ├── extension.ts       # Main extension entry point - handles activation, LSP setup, formatting middleware
│   ├── util.ts            # Utility functions (ZLS path detection)
│   └── fmt/               # Formatting logic
│       ├── fmt.ts         # Main formatting orchestrator (formatZx, formatZig, formatHtml)
│       └── util.ts        # Formatting utilities (HTML extraction, expression parsing)
├── syntaxes/              # TextMate grammar files for syntax highlighting
│   ├── zx.tmLanguage.json      # Main ZX syntax definition
│   └── zx-injection.tmLanguage.json  # Injection grammar for embedded content
├── test/                  # Test suite
│   ├── fmt/               # Formatting tests
│   └── data.test.ts       # Data structure tests
├── images/                # Extension icons
└── language-configuration.json  # VS Code language configuration (brackets, comments, etc.)
```

#### Why This Structure?

- **`src/extension.ts`**: Centralizes VS Code API integration and extension lifecycle management
- **`src/fmt/`**: Separates formatting concerns into a dedicated module with clear responsibilities
- **`syntaxes/`**: Uses TextMate grammars (standard for VS Code) to define language syntax
- **Virtual document providers**: Enable formatting of embedded HTML/Zig by creating temporary documents that VS Code's formatters can process

### How Things Work

#### Data Flow: Formatting Pipeline

The formatting system follows a sophisticated pipeline to handle the mixed Zig/HTML nature of ZX files:

```
1. User triggers format (Cmd+Shift+P → Format Document)
   │
   └─→ extension.ts: provideFormattingEdits()
       │
       └─→ fmt.ts: formatZx()
           │
           ├─→ Step 1: Extract HTML blocks
           │   └─→ util.ts: extractHtmls()
           │       • Scans document for HTML tags inside parentheses
           │       • Replaces HTML with placeholders (<html:N />)
           │       • Returns prepared Zig code + HTML map
           │
           ├─→ Step 2: Format Zig code
           │   └─→ fmt.ts: formatZig()
           │       └─→ runZigFmt() (uses zig fmt CLI or ZLS)
           │
           ├─→ Step 3: Format HTML blocks
           │   └─→ fmt.ts: formatHtml()
           │       ├─→ Extract Zig expressions from HTML
           │       ├─→ Recursively format nested HTML (if any)
           │       ├─→ Format Zig expressions (if enabled)
           │       └─→ Use vscode-html-languageservice to format HTML
           │
           └─→ Step 4: Merge everything back
               └─→ patchInFormattedHtml()
                   • Replaces placeholders with formatted HTML
                   • Returns complete formatted document
```

#### Key Components

1. **Language Server Integration**
   - Uses ZLS (Zig Language Server) from the official Zig extension
   - Provides diagnostics, hover, and other LSP features
   - Filters out false positives (e.g., "expected expression, found '<'" for ZX syntax)

2. **Virtual Document Providers**
   - Creates temporary virtual documents for embedded HTML/Zig content
   - Allows VS Code's HTML formatter to process HTML blocks in isolation
   - Uses URI schemes: `embedded-content-fmt-html://` and `embedded-content-fmt-zig://`

3. **HTML Extraction Logic**
   - Tracks string boundaries to avoid false matches
   - Only extracts HTML inside parentheses (ZX syntax requirement)
   - Uses `vscode-html-languageservice` scanner to identify HTML tags

4. **Recursive Formatting**
   - Handles nested HTML inside Zig expressions
   - Formats inner HTML blocks before formatting the containing Zig expression
   - Maintains proper indentation across nested levels

### How to Contribute

#### Setup

##### Prerequisites

- **Bun.js** - We use it for testing
- **Zig** - We use it for formatting
- **VS Code** - We use it for development

1. **Clone and install dependencies:**

   ```bash
   git clone https://github.com/nurulhudaapon/zx-vscode.git
   cd zx-vscode
   npm install
   ```

2. **Compile TypeScript:**

   ```bash
   npm run compile
   # Or watch mode for development:
   npm run watch
   ```

3. **Open in VS Code:**
   - Open the project folder in VS Code
   - Press `F5` to launch a new Extension Development Host window
   - In the new window, open a `.zx` file to test the extension

#### Making Changes

**Adding Syntax Highlighting:**

- Edit `syntaxes/zx.tmLanguage.json` or `syntaxes/zx-injection.tmLanguage.json`
- TextMate grammar syntax: https://macromates.com/manual/en/language_grammars

**Modifying Formatting:**

- Main logic: `src/fmt/fmt.ts`
- Utilities: `src/fmt/util.ts`
- Test your changes with the test suite (see below)

**Changing Extension Behavior:**

- Entry point: `src/extension.ts`
- Add commands in `package.json` under `contributes.commands`
- Register handlers in `activate()` function

#### Testing

Have 'bun.js' installed as we use it for testing.
Run the test suite:

```bash
npm test
```

Test files are located in `test/`:

- `test/fmt/fmt.test.ts` - Formatting function tests
- `test/fmt/util.test.ts` - Utility function tests
- `test/data.test.ts` - Data structure and edge case tests

**Manual Testing:**

1. Launch extension in development mode (`F5`)
2. Create test `.zx` files with various patterns
3. Test formatting, syntax highlighting, and LSP features
4. Check the Output panel → "ZX Language Server" for logs

#### Submitting Contributions

1. Create a branch and make your changes
2. Format code: `npm run fmt`
3. Run tests: `npm test`
4. Open a Pull Request with a clear description

#### Areas That Need Help

- **Syntax highlighting improvements**: Better recognition of edge cases
- **Formatting edge cases**: Handling complex nested structures
- **Performance optimization**: Faster formatting for large files
- **LSP features**: See detailed checklist below

#### LSP Features Checklist

The following LSP features need implementation to provide a better development experience:

**HTML Block Support:**

- [ ] Diagnostics for HTML syntax errors within ZX files
- [ ] Autocomplete for HTML tags and attributes inside HTML blocks
- [ ] Hover information for HTML elements (showing tag documentation, attribute descriptions)
- [ ] Go to definition for HTML components/imports
- [ ] Semantic highlighting for HTML content

**ZX File Analysis via ZLS:**

- [ ] Transform `.zx` files to `.zig` format for ZLS processing
- [ ] Create virtual document provider that converts ZX → Zig on-the-fly
- [ ] Map ZLS diagnostics back to original ZX file positions
- [ ] Handle ZX-specific syntax in Zig transformation (preserve HTML blocks as comments or special markers)
- [ ] Support for `.zx` file imports in Zig code analysis
- [ ] Type checking and diagnostics for Zig expressions within HTML blocks

**Virtual Document Provider for ZLS:**

- [ ] Implement `TextDocumentContentProvider` for `zx://` URI scheme
- [ ] Convert ZX syntax to valid Zig code that ZLS can understand
- [ ] Preserve source mapping between virtual Zig and original ZX positions
- [ ] Handle nested HTML blocks in Zig expressions
- [ ] Support incremental document updates
- [ ] Cache transformed documents for performance

**Integration Points:**

- [ ] Register virtual document provider in `extension.ts`
- [ ] Configure ZLS to accept virtual Zig documents
- [ ] Map LSP responses (diagnostics, hover, completion) back to ZX positions
- [ ] Handle edge cases (empty files, syntax errors, malformed HTML)

**Testing Requirements:**

- [ ] Test virtual document transformation accuracy
- [ ] Test position mapping (Zig → ZX)
- [ ] Test diagnostics propagation
- [ ] Test autocomplete in various contexts (HTML, Zig expressions, mixed)
- [ ] Test hover information accuracy
