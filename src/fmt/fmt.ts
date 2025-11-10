import * as childProcess from "child_process";
import * as util from "util";
import {
  getLanguageService,
  HTMLFormatConfiguration,
  TextDocument,
} from "vscode-html-languageservice";
const htmlLanguageService = getLanguageService();
import * as fmtUtil from "./util";
const {
  findBalancedParens,
  indentNegate,
  removeSemicolonsFromHtmlPlaceholders,
  removeSemicolonsFromCompleteExpressions,
} = fmtUtil;

const execFile = util.promisify(childProcess.execFile);

const htmlFormatConfig: HTMLFormatConfiguration = {
  tabSize: 4,
  insertSpaces: true,
};

/* ============================================================================
[Input Document]
       |
       v
[Choose Formatting Function]
       |
       +-------------------+
       |                   |
       v                   v
[formatZx]           [formatZig]
       |                   |
       v                   v
[Processing Logic]   [Processing Logic]
       |                   |
       v                   v
[Output Document]   [Output Document]
       |
       v
[formatHtml]
       |
       v
[Processing Logic]
       |
       v
[Output Document]
**/

/**
 * Main entry point for formatting ZX code.
 * Orchestrates the formatting of both Zig and HTML content.
 */
export async function formatZx(
  documentText: string,
  token: CancellationToken,
  originalUri: string,
  virtualHtmlDocumentContents: Map<string, string>,
): Promise<string> {
  fmtStats.increment("fmt");

  // Step 1: Extract HTML and get prepared Zig code
  const htmlExtractedDoc = extractHtmls(documentText);

  // Step 2: Format the Zig code
  const formattedZigCode = await formatZig(
    htmlExtractedDoc.preparedDocumentText,
    token,
  );

  // Step 3: Format HTML sections
  const formattedHtmlContents = new Map<string, string>();

  for (const [key, htmlContent] of htmlExtractedDoc.htmlContents.entries()) {
    const formattedHtml = await formatHtml(
      htmlContent,
      key,
      token,
      originalUri,
      virtualHtmlDocumentContents,
    );
    formattedHtmlContents.set(key, formattedHtml);
  }

  // Step 4: Merge formatted Zig code and HTML back together
  const result = patchInFormattedHtml(formattedZigCode, formattedHtmlContents);

  return result;
}

/**
 * Formats Zig code by preparing it and applying Zig formatter (ZLS or zig fmt CLI).
 */
export async function formatZig(
  preparedZigText: string,
  token: CancellationToken,
): Promise<string> {
  return runZigFmt(preparedZigText, token);
}

/**
 * Formats HTML content, including any embedded Zig expressions within it.
 */
export async function formatHtml(
  htmlContent: string,
  htmlKey: string,
  token: CancellationToken,
  originalUri: string,
  virtualHtmlDocumentContents: Map<string, string>,
): Promise<string> {
  
  // Read configuration: formatting of embedded Zig expressions (and inner HTML)
  // is opt-in via `zx.format.enableZigExpression`. Default is false (disabled)
  // to avoid triggering known formatting bugs. When false, we preserve embedded
  // expressions as-is. When true, the formatter will attempt to format them.

  // First, extract zig expressions inside this HTML block
  const zigExpressions = extractZigExprs(htmlContent);
  // segment.preparedSegmentText contains <zig:N /> placeholders instead of zig expressions

  // For each zig segment, we need to format it. Zig segments themselves may contain HTML, so
  // we must run prepareFmtDoc on each segment and format inner html, then format the zig.
  const formattedZigExpressions = new Map<string, string>();
  
  // Collect all prepared documents and their inner formatted HTML maps
  const preparedDocuments: Array<{
    zigKey: string;
    preparedText: string;
    innerFormattedHtml: Map<string, string>;
  }> = [];

  for (const [zigKey, zigText] of zigExpressions.exprss.entries()) {
    // Prepare inner HTML inside this zigText
    const innerPrepared = extractHtmls(zigText);

    // Format inner HTML blocks inside this zig segment
    const innerFormattedHtml = new Map<string, string>();
    for (const [innerKey, innerHtml] of innerPrepared.htmlContents.entries()) {
      const innerVirtualKey = originalUri + htmlKey + zigKey + innerKey;
      virtualHtmlDocumentContents.set(innerVirtualKey, innerHtml);

      const innerHtmlVirtualUri = `embedded-content-fmt-html://html/${encodeURIComponent(innerVirtualKey)}.html`;
      const innerVirtualHtmlDoc = TextDocument.create(
        innerHtmlVirtualUri.toString(),
        "html",
        0,
        innerHtml,
      );
      const innerHtmlTextEdits = htmlLanguageService.format(
        innerVirtualHtmlDoc,
        undefined,
        htmlFormatConfig,
      );
      const innerFormatted = TextDocument.applyEdits(
        innerVirtualHtmlDoc,
        innerHtmlTextEdits,
      );
      innerFormattedHtml.set(innerKey, innerFormatted);
    }

    // Collect prepared document for batch formatting
    preparedDocuments.push({
      zigKey,
      preparedText: innerPrepared.preparedDocumentText,
      innerFormattedHtml,
    });
  }

  // Format all zig expressions at once
  const formattedPreparedZigArray = preparedDocuments.length > 0
    ? await formatZigExprsBatch(
        preparedDocuments.map(doc => doc.preparedText),
        token,
      )
    : [];

  // Put back inner formatted HTML into the formatted zig text for each expression
  for (let i = 0; i < preparedDocuments.length; i++) {
    const { zigKey, innerFormattedHtml } = preparedDocuments[i];
    const formattedPreparedZig = formattedPreparedZigArray[i];

    const formattedZigWithHtml = patchInFormattedHtml(
      formattedPreparedZig,
      innerFormattedHtml,
    );

    formattedZigExpressions.set(zigKey, formattedZigWithHtml);
  }

  // Now we have formatted zig segments. Replace <zig:N /> placeholders in the segment.preparedSegmentText
  let htmlWithZigPlaceholders = zigExpressions.preparedSegmentText;

  // Store HTML content (with formatted zig segments inserted) in virtual HTML map so the HTML formatter can see it
  const virtualHtmlKey = originalUri + htmlKey;
  virtualHtmlDocumentContents.set(virtualHtmlKey, htmlWithZigPlaceholders);

  const htmlVirtualUri = `embedded-content-fmt-html://html/${encodeURIComponent(virtualHtmlKey)}.html`;

  const virtualHtmlDoc = TextDocument.create(
    htmlVirtualUri.toString(),
    "html",
    0,
    htmlWithZigPlaceholders,
  );

  const timestamp = Date.now();
  const htmlTextEdits = htmlLanguageService.format(
    virtualHtmlDoc,
    undefined,
    htmlFormatConfig,
  );
  let formattedHtml = TextDocument.applyEdits(virtualHtmlDoc, htmlTextEdits);
  fmtStats.increment("html", Date.now() - timestamp);

  // There may be remaining raw <zig:N /> placeholders if any; ensure formattedZigSegments are reinserted
  // When replacing, preserve the indentation of the placeholder line
  for (const [zigKey, formattedZig] of formattedZigExpressions.entries()) {
    formattedHtml = formattedHtml.replace(zigKey, (match) => {
      // Find the line containing the placeholder to get its indentation
      const lines = formattedHtml.split("\n");
      let placeholderIndent = "";

      for (const line of lines) {
        if (line.includes(zigKey)) {
          // Extract the leading whitespace from the line containing the placeholder
          const indentMatch = line.match(/^(\s*)/);
          placeholderIndent = indentMatch ? indentMatch[1] : "";
          break;
        }
      }

      // Transform the formatted Zig expression to remove extra line breaks and adjust indentation
      const transformedZig = cleanupZigExprs(
        formattedZig,
        htmlFormatConfig.tabSize,
        htmlFormatConfig.insertSpaces,
      );

      // Apply the indentation to all lines of the transformed Zig expression
      const zigLines = transformedZig.split("\n");
      const indentedZigLines = zigLines.map((line, index) => {
        // First line already has correct indentation from the placeholder position
        if (index === 0) return line;
        // Last line with closing braces - remove extra indentation and align with opening brace
        if (index === zigLines.length - 1) {
          const trimmed = line.trim();
          // If it's just closing braces, use placeholder indentation (same as first line)
          if (trimmed.match(/^}+$/)) {
            return placeholderIndent + trimmed;
          }
        }
        // Subsequent lines need the same indentation as the placeholder
        return line ? placeholderIndent + line : line;
      });

      // Ensure closing braces are on the same line (in case they got split)
      // If the last two lines are just closing braces, merge them
      if (indentedZigLines.length >= 2) {
        const lastLine = indentedZigLines[indentedZigLines.length - 1];
        const secondLastLine = indentedZigLines[indentedZigLines.length - 2];
        if (lastLine.trim() === "}" && secondLastLine.trim().endsWith("}")) {
          // Merge the closing braces using placeholder indentation (same as first line)
          const merged = secondLastLine.trimEnd().slice(0, -1) + "}}";
          indentedZigLines[indentedZigLines.length - 2] =
            placeholderIndent + merged.trim();
          indentedZigLines.pop();
        } else if (lastLine.trim() === "}" && indentedZigLines.length === 2) {
          // For one-liner if expressions (no blocks), merge closing brace with previous line
          // Check if this is a one-liner if expression by checking if there's only one opening brace
          const firstLineContent = indentedZigLines[0].trim();
          if (firstLineContent.startsWith("{if") && firstLineContent.match(/\{/g)?.length === 1) {
            // Merge the closing brace with the previous line
            indentedZigLines[0] = indentedZigLines[0].trimEnd() + "}";
            indentedZigLines.pop();
          }
        }
      }

      return indentedZigLines.join("\n");
    });
  }

  return formattedHtml;
}

// ============================================================================
// HELPER FUNCTIONS - Document preparation and transformation
// ============================================================================

type PreparedFmtDoc = {
  preparedDocumentText: string;
  htmlContents: Map<string, string>;
};

/**
 * Prepares a ZX document for formatting by extracting HTML blocks and replacing them with placeholders.
 * This allows the Zig formatter to work on the code without being confused by HTML syntax.
 */
export function extractHtmls(documentText: string): PreparedFmtDoc {
  const htmlContents = new Map<string, string>();
  let preparedDocumentText = documentText;
  const result = fmtUtil.extractHtmls(documentText);


  result.htmls.forEach((html, index) => {
    htmlContents.set(`@html(${index})`, html);
    preparedDocumentText = preparedDocumentText.replace(html, `@html(${index})`);
  });

  return { preparedDocumentText, htmlContents };
}

/**
 * Replaces HTML placeholders in formatted Zig code with the actual formatted HTML content.
 */
export function patchInFormattedHtml(
  formattedText: string,
  htmlContents: Map<string, string>,
): string {
  let result = formattedText;

  for (const [key, htmlContent] of htmlContents.entries()) {
    let replacement = htmlContent;
    const isMultiLine = htmlContent.includes("\n");
    if (isMultiLine) {
      const lines = result.split("\n");
      const keyLineIndex = lines.findIndex((line) => line.includes(key));
      const keyLine = keyLineIndex >= 0 ? lines[keyLineIndex] : "";
      const currentKeyIndentation = keyLine.match(/^\s*/)?.[0] || "";

      // Check if the key is inside a for loop by looking backwards from the key line
      let isInsideForLoop = false;
      if (keyLineIndex >= 0) {
        // Look backwards from the key line to find if we're inside a for loop
        for (let i = keyLineIndex; i >= 0; i--) {
          const line = lines[i];
          // Check if this line contains a for loop opening
          if (/\bfor\s*\(/.test(line)) {
            // Find the opening brace after the for statement
            let openingBraceLine = -1;
            let openingBracePos = -1;
            for (let j = i; j <= keyLineIndex; j++) {
              const currentLine = lines[j];
              const braceIndex = currentLine.indexOf("{");
              if (braceIndex !== -1) {
                openingBraceLine = j;
                openingBracePos = braceIndex;
                break;
              }
            }

            if (openingBraceLine === -1) {
              // No opening brace found, not inside for loop
              break;
            }

            // Count braces from the opening brace to the key line
            let braceCount = 1; // We start with the opening brace
            for (let j = openingBraceLine; j <= keyLineIndex; j++) {
              const currentLine = lines[j];
              const startPos = j === openingBraceLine ? openingBracePos + 1 : 0;
              for (let k = startPos; k < currentLine.length; k++) {
                const char = currentLine[k];
                if (char === "{") {
                  braceCount++;
                } else if (char === "}") {
                  braceCount--;
                  if (braceCount === 0) {
                    // We've closed the opening brace before reaching the key
                    break;
                  }
                }
              }
              if (braceCount === 0) {
                break;
              }
            }

            // If we're still inside braces (braceCount > 0), we're in a for loop
            if (braceCount > 0) {
              isInsideForLoop = true;
            }
            break;
          }
        }
      }

      if (isInsideForLoop) {
        // For for loops, use single indentation level and no extra newlines
        const indentedHtmlContent = htmlContent
          .split("\n")
          .map((line) => {
            return currentKeyIndentation + line;
          })
          .join("\n");

        replacement = indentedHtmlContent;
      } else {
        // For other cases (if/else), use double indentation and add newlines
        const indentedHtmlContent = htmlContent
          .split("\n")
          .map((line) => {
            return currentKeyIndentation.repeat(2) + line;
          })
          .join("\n");

        replacement = `\n${indentedHtmlContent}\n${currentKeyIndentation}`;
      }
    }

    result = result.replace(key, replacement);
  }

  return result;
}

type PreparedFmtSegment = {
  exprss: Map<string, string>;
  preparedSegmentText: string;
};

/**
 * Prepares an HTML segment for formatting by extracting Zig expressions (for/if/switch) and replacing them with placeholders.
 */
export function extractZigExprs(documentText: string): PreparedFmtSegment {
  const zigSegments = new Map<string, string>();
  let preparedSegmentText = documentText;

  // Find all zig expressions: { for (...) } or { if (...) } or { switch (...) }
  // Allow optional whitespace/newlines right after the opening '{'.
  // These can include capture variables like { for (items) |item| (...) }
  const zigExpressionRegex = /{\s*(for|if|switch)\s*\(/g;
  let match;
  const matches: Array<{ start: number; end: number; fullMatch: string }> = [];

  // First, collect all opening expressions with their positions
  while ((match = zigExpressionRegex.exec(documentText)) !== null) {
    const keyword = match[1];
    const start = match.index;
    let pos = match.index + match[0].length; // Position after "{for (" or "{if (" or "{switch ("

    // Find the matching closing parenthesis for the condition
    let parenDepth = 1;
    while (pos < documentText.length && parenDepth > 0) {
      if (documentText[pos] === "(") parenDepth++;
      else if (documentText[pos] === ")") parenDepth--;
      pos++;
    }

    if (parenDepth !== 0) continue; // No matching closing paren found

    // Skip whitespace after the closing paren
    while (pos < documentText.length && /\s/.test(documentText[pos])) {
      pos++;
    }

    // Check for optional capture variable |variable|
    if (documentText[pos] === "|") {
      pos++; // Skip opening |
      // Find closing |
      const captureEnd = documentText.indexOf("|", pos);
      if (captureEnd !== -1) {
        pos = captureEnd + 1;
        // Skip whitespace after capture variable
        while (pos < documentText.length && /\s/.test(documentText[pos])) {
          pos++;
        }
      }
    }

    // Now find the body and matching closing brace
    // The body is wrapped in parentheses, then the whole expression ends with }
    let braceDepth = 1; // We're already inside one opening brace

    // Find the body which is wrapped in parentheses
    if (documentText[pos] === "(") {
      // Find matching closing paren for the body
      let bodyParenDepth = 1;
      pos++; // Skip opening paren
      while (pos < documentText.length && bodyParenDepth > 0) {
        const char = documentText[pos];
        if (char === "(") {
          bodyParenDepth++;
        } else if (char === ")") {
          bodyParenDepth--;
        } else if (char === "{") {
          braceDepth++; // Track nested braces inside body
        } else if (char === "}") {
          braceDepth--; // Track nested braces inside body
        }
        pos++;
      }
    }

    // Now find the closing brace for the entire expression
    while (pos < documentText.length && braceDepth > 0) {
      const char = documentText[pos];
      if (char === "{") {
        braceDepth++;
      } else if (char === "}") {
        braceDepth--;
      }
      pos++;
    }

    if (braceDepth === 0) {
      // Found the matching closing brace
      const end = pos;
      const fullMatch = documentText.substring(start, end);
      matches.push({ start, end, fullMatch });
    }
  }

  // Replace matches from end to start to avoid position shifts
  for (let i = matches.length - 1; i >= 0; i--) {
    const match = matches[i];
    const index = zigSegments.size;
    const key = `<zig:${index} />`;

    zigSegments.set(key, match.fullMatch);
    preparedSegmentText =
      preparedSegmentText.substring(0, match.start) +
      key +
      preparedSegmentText.substring(match.end);
  }

  return { exprss: zigSegments, preparedSegmentText };
}

/**
 * Transforms formatted Zig code to remove extra line breaks and adjust indentation.
 * Merges opening { with the next line and closing } with the previous line,
 * then removes one level of indentation from middle lines.
 */
export function cleanupZigExprs(
  formattedZig: string,
  tabSize: number = 4,
  insertSpaces: boolean = true,
): string {
  let zigLines = formattedZig.split("\n");

  // Check if this is a one-liner if expression (no blocks, just parentheses)
  // A one-liner if expression would be: {if (condition) (value) else (value)}
  // We detect this by checking if there are no opening braces after the if keyword
  // (except the outer opening brace)
  const isOneLinerIf = (() => {
    const fullText = zigLines.join("\n");
    const trimmed = fullText.trim();
    if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) {
      return false;
    }
    // Check if it's an if expression
    const ifMatch = trimmed.match(/^\{if\s*\(/);
    if (!ifMatch) {
      return false;
    }
    // Check if there are no block braces (only the outer ones)
    // Count opening braces - should be exactly 1 (the outer one)
    const openBraces = (trimmed.match(/\{/g) || []).length;
    const closeBraces = (trimmed.match(/\}/g) || []).length;
    // For a one-liner, we should have exactly 1 opening and 1 closing brace
    // (the outer ones), and no block braces inside
    if (openBraces === 1 && closeBraces === 1) {
      return true;
    }
    return false;
  })();

  // Remove line break after opening curly: merge { with next line if first line is just {
  if (zigLines.length > 1 && zigLines[0].trim() === "{") {
    const secondLine = zigLines[1];
    // Merge opening brace with the next line
    zigLines[0] = "{" + secondLine.trimStart();
    zigLines.splice(1, 1);
  }

  // Remove line break before closing curly: merge } with previous line if last line is just }
  // Handle consecutive closing braces by merging them together
  while (zigLines.length > 1 && zigLines[zigLines.length - 1].trim() === "}") {
    const lastIndex = zigLines.length - 1;
    const prevLine = zigLines[lastIndex - 1];
    const prevLineTrimmed = prevLine.trimEnd();

    // If previous line ends with }, merge into }} (preserve indentation)
    if (prevLineTrimmed.endsWith("}")) {
      // Get the indentation from the previous line
      const indent = prevLine.slice(
        0,
        prevLine.length - prevLineTrimmed.length,
      );
      // Replace the trailing } with }}
      zigLines[lastIndex - 1] = indent + prevLineTrimmed.slice(0, -1) + "}}";
    } else {
      // Otherwise, just append } to the previous line
      zigLines[lastIndex - 1] = prevLine.trimEnd() + "}";
    }
    zigLines.pop();
  }

  // For one-liner if expressions, ensure everything stays on one line
  if (isOneLinerIf && zigLines.length > 1) {
    // Merge all lines into one, preserving the first line's indentation
    const firstLine = zigLines[0];
    const indentMatch = firstLine.match(/^(\s*)/);
    const indent = indentMatch ? indentMatch[1] : "";
    const content = zigLines.map((line, idx) => {
      if (idx === 0) return line.trim();
      return line.trim();
    }).join(" ").trim();
    zigLines = [indent + content];
  }

  // Apply indentNegate to remove one level of indentation from lines 1 to lineCount - 1
  // This includes the last line (which may have been merged with closing brace)
  if (zigLines.length > 1) {
    zigLines = indentNegate(
      zigLines,
      1,
      zigLines.length - 1,
      1,
      tabSize,
      insertSpaces,
    );
  }

  // Join lines and remove any trailing newline
  return zigLines.join("\n").replace(/\n+$/, "");
}


/**
 * Adds semicolons after complete expression statements (if/for/switch/while) to make valid Zig syntax.
 * This handles expressions like: if (condition) (value) else (value)
 * and converts them to: if (condition) (value) else (value);
 */
export function addSemicolonsToCompleteExpressions(text: string): string {
  type ExpressionType = "if" | "for" | "switch" | "while";
  
  const expressionKeywords: ExpressionType[] = ["if", "for", "switch", "while"];
  const matches: Array<{ start: number; end: number; type: ExpressionType }> = [];

  // Find all expression keywords
  for (const keyword of expressionKeywords) {
    const regex = new RegExp(`\\b${keyword}\\s*\\(`, "g");
    let match;
    while ((match = regex.exec(text)) !== null) {
      const start = match.index;
      const afterKeyword = match.index + match[0].length - 1; // Position of opening '('
      
      // Find the end of the condition parentheses
      const conditionEnd = findBalancedParens(text, afterKeyword);
      if (conditionEnd === -1) continue;

      // Skip whitespace after condition
      let pos = conditionEnd;
      while (pos < text.length && /\s/.test(text[pos])) {
        pos++;
      }

      // Check for optional capture variable |variable|
      if (text[pos] === '|') {
        pos++; // Skip opening |
        const captureEnd = text.indexOf('|', pos);
        if (captureEnd !== -1) {
          pos = captureEnd + 1;
          // Skip whitespace after capture variable
          while (pos < text.length && /\s/.test(text[pos])) {
            pos++;
          }
        }
      }

      // Handle body that may start with { then ( (e.g., {(\n ... \n)})
      let bodyStartPos = pos;
      if (text[pos] === '{') {
        // Skip opening brace and whitespace
        bodyStartPos = pos + 1;
        while (bodyStartPos < text.length && /\s/.test(text[bodyStartPos])) {
          bodyStartPos++;
        }
      }

      // Find the body which is wrapped in parentheses
      if (text[bodyStartPos] === '(') {
        const bodyEnd = findBalancedParens(text, bodyStartPos);
        if (bodyEnd === -1) continue;

        let end = bodyEnd;

        // For if expressions, check for else clause
        if (keyword === "if") {
          // Skip whitespace after body
          let elsePos = bodyEnd;
          while (elsePos < text.length && /\s/.test(text[elsePos])) {
            elsePos++;
          }

          // Check for else
          if (text.substring(elsePos, elsePos + 4) === "else") {
            elsePos += 4;
            // Skip whitespace after else
            while (elsePos < text.length && /\s/.test(text[elsePos])) {
              elsePos++;
            }

            // Find else body
            if (text[elsePos] === '(') {
              const elseBodyEnd = findBalancedParens(text, elsePos);
              if (elseBodyEnd !== -1) {
                end = elseBodyEnd;
              }
            }
          }
        }

        matches.push({ start, end, type: keyword });
      }
    }
  }

  // Process matches from end to start to avoid position shifts
  let result = text;
  for (let i = matches.length - 1; i >= 0; i--) {
    const { start, end, type } = matches[i];

    // Check if this is already followed by a semicolon
    const afterMatch = result.slice(end);
    const trimmedAfter = afterMatch.trimStart();

    // If already has semicolon, skip
    if (trimmedAfter.startsWith(";")) {
      continue;
    }

    // Skip if followed by opening brace (it's part of a block)
    if (trimmedAfter.startsWith("{")) {
      continue;
    }

    // Skip if followed by another expression keyword
    if (/^\s*(if|for|while|switch)\s*\(/.test(trimmedAfter)) {
      continue;
    }

    // Check if we're at the end of a line or followed by semicolon/newline/brace
    // This indicates it's a complete statement
    const isCompleteStatement =
      trimmedAfter === "" ||
      trimmedAfter.startsWith("\n") ||
      trimmedAfter.startsWith(";") ||
      trimmedAfter.startsWith("}");

    // Check if this expression is inside braces (HTML expression context)
    // by looking backwards for an opening brace before the expression
    const beforeExpr = result.slice(0, start);
    const lastOpenBrace = beforeExpr.lastIndexOf("{");
    const lastCloseBrace = beforeExpr.lastIndexOf("}");
    const isInsideBraces = lastOpenBrace > lastCloseBrace;

    if (isCompleteStatement && !isInsideBraces) {
      // Switch statements don't require semicolons
      if (type === "switch") {
        continue;
      }

      // Add semicolon after the complete expression
      result = result.slice(0, end) + ";" + result.slice(end);
    } else if (isCompleteStatement && isInsideBraces) {
      // For expressions inside braces (HTML context), we still add semicolons
      // temporarily to make valid Zig for formatting, but they'll be removed later
      // Switch statements don't require semicolons
      if (type === "switch") {
        continue;
      }

      // Add semicolon after the complete expression (will be removed after formatting)
      result = result.slice(0, end) + ";" + result.slice(end);
    }
  }

  return result;
}

/**
 * Adds semicolons after @html(n) patterns inside control flow statements to make valid Zig syntax.
 * This is needed because inside if/else/for/while blocks, expressions need semicolons.
 * Note: switch statements do NOT require semicolons, so they are excluded.
 */
export function addSemicolonsToHtmlPlaceholders(text: string): string {
  // Match @html(n) or (@html(n)) patterns
  const htmlPattern = /(@html\(\d+\)|\(@html\(\d+\)\))/g;
  const matches: Array<{ match: string; index: number }> = [];

  // Collect all matches with their positions
  let match;
  while ((match = htmlPattern.exec(text)) !== null) {
    matches.push({ match: match[0], index: match.index });
  }

  // Process matches from end to start to avoid position shifts
  let result = text;
  for (let i = matches.length - 1; i >= 0; i--) {
    const { match: htmlMatch, index } = matches[i];

    // Check if this is already followed by a semicolon
    const afterMatch = result.slice(index + htmlMatch.length);
    const trimmedAfter = afterMatch.trimStart();

    // If already has semicolon, skip
    if (trimmedAfter.startsWith(";")) {
      continue;
    }

    // Check if we're inside a control flow block by looking backwards for if/else/for/while
    // and checking if we're inside braces
    // Note: switch statements are excluded as they don't require semicolons
    const beforeMatch = result.slice(0, index);

    // Find all control flow keywords before this position
    const controlFlowMatches: Array<{ keyword: string; index: number }> = [];

    // Use switch case for different expression types
    const expressionTypes: Array<{ keyword: string; regex: RegExp }> = [
      { keyword: "if", regex: /\bif\s*\(/g },
      { keyword: "for", regex: /\bfor\s*\(/g },
      { keyword: "while", regex: /\bwhile\s*\(/g },
      { keyword: "else", regex: /\belse\s*{/g },
      { keyword: "switch", regex: /\bswitch\s*\(/g },
    ];

    for (const { keyword, regex } of expressionTypes) {
      let m;
      while ((m = regex.exec(beforeMatch)) !== null) {
        controlFlowMatches.push({ keyword, index: m.index });
      }
    }

    // Find the closest control flow keyword
    if (controlFlowMatches.length === 0) {
      continue;
    }

    // Sort by index descending to get the closest (last) one
    controlFlowMatches.sort((a, b) => b.index - a.index);
    const closestControlFlow = controlFlowMatches[0];

    // If the closest control flow is a switch, skip adding semicolon
    if (closestControlFlow.keyword === "switch") {
      continue;
    }

    const lastControlFlowPos = closestControlFlow.index;

    // Check if we're inside braces after the control flow keyword
    // Find the opening brace of the control flow block and count braces to our position
    const afterControlFlow = beforeMatch.slice(lastControlFlowPos);
    let braceCount = 0;
    let foundOpeningBrace = false;
    let openingBracePos = -1;

    // Find the opening brace after the control flow keyword
    for (let j = 0; j < afterControlFlow.length; j++) {
      const char = afterControlFlow[j];
      if (char === "{") {
        openingBracePos = j;
        foundOpeningBrace = true;
        braceCount = 1;
        break;
      }
    }

    if (!foundOpeningBrace) {
      continue;
    }

    // Count braces from the opening brace to our position
    for (let k = openingBracePos + 1; k < afterControlFlow.length; k++) {
      const char = afterControlFlow[k];
      if (char === "{") {
        braceCount++;
      } else if (char === "}") {
        braceCount--;
        if (braceCount === 0) {
          // We've closed the opening brace before reaching our position
          break;
        }
      }
    }

    // If we're still inside the opening brace (braceCount > 0), check if we're inside parentheses
    // If we're inside parentheses that are part of a control flow body, skip adding semicolon here
    // because addSemicolonsToCompleteExpressions will add it after the closing paren
    if (braceCount > 0) {
      // Check if we're inside parentheses by looking backwards from the @html position
      // Convert openingBracePos to absolute position in result string
      const absoluteOpeningBracePos = lastControlFlowPos + openingBracePos;
      let parenCount = 0;
      let foundOpeningParen = false;
      let parenStartPos = -1;
      
      // Look backwards from the @html position to find if we're inside parentheses
      for (let k = index - 1; k >= absoluteOpeningBracePos; k--) {
        const char = result[k];
        if (char === ")") {
          parenCount++;
        } else if (char === "(") {
          if (parenCount === 0) {
            // Found the opening paren that contains us
            foundOpeningParen = true;
            parenStartPos = k;
            break;
          }
          parenCount--;
        }
      }
      
      // If we're inside parentheses that start after the opening brace, skip adding semicolon
      // The semicolon will be added by addSemicolonsToCompleteExpressions after the closing paren
      if (foundOpeningParen && parenStartPos > absoluteOpeningBracePos) {
        continue;
      }
      
      result =
        result.slice(0, index + htmlMatch.length) +
        ";" +
        result.slice(index + htmlMatch.length);
    }
  }

  return result;
}


/**
 * Formats multiple prepared Zig text segments at once (which may still contain @html(...) placeholders).
 * Concatenates all segments with "test " prefix and newlines, formats them all at once,
 * then splits by "test " keyword to extract individual formatted expressions.
 */
async function formatZigExprsBatch(
  preparedZigTexts: string[],
  token: CancellationToken,
): Promise<string[]> {
  if (preparedZigTexts.length === 0) {
    return [];
  }

  // Add semicolons after complete expressions and @html(n) patterns to make valid Zig for each text
  const textsWithSemicolons = preparedZigTexts.map(text =>
    addSemicolonsToCompleteExpressions(
      addSemicolonsToHtmlPlaceholders(text)
    )
  );

  // Concatenate all texts with "test " prefix and newlines
  const validZigDoc = textsWithSemicolons
    .map(text => "test " + text)
    .join("\n");

  // Format all at once
  const formattedEdits = await runZigFmt(validZigDoc, token);

  // Split by "test " keyword to extract individual formatted expressions
  // The formatted text will have "test " at the start and after each newline
  let formattedText = formattedEdits.trim();
  
  // Remove leading "test " if present
  if (formattedText.startsWith("test ")) {
    formattedText = formattedText.slice("test ".length);
  }
  
  // Split by "\ntest " to get individual expressions
  const parts = formattedText.split(/\ntest /);
  
  // Process each part
  const formattedExpressions: string[] = [];
  for (const part of parts) {
    const trimmed = part.trim();
    if (trimmed.length === 0) {
      continue;
    }
    
    // Remove semicolons we added before formatting
    const cleaned = removeSemicolonsFromCompleteExpressions(
      removeSemicolonsFromHtmlPlaceholders(trimmed)
    );
    
    formattedExpressions.push(cleaned);
  }

  return formattedExpressions;
}

/**
 * Ensures that `zig fmt` has been JIT compiled by running `zig fmt --help`.
 * This warms up the zig process to avoid the JIT compilation delay on the first format request.
 */
export function preCompileZigFmt(): void {
  try {
    childProcess.execFile("zig", ["fmt", "--help"], {
      timeout: 60000, // 60 seconds (this is a very high value because 'zig fmt' is just in time compiled)
    });
  } catch (err) {
    // Silently ignore errors - warming is best effort
    // The actual format operation will handle errors appropriately
  }
}

/**
 * Runs `zig fmt --stdin` on prepared text. Returns formatted text or original on failure.
 */
export async function runZigFmt(
  text: string,
  token: CancellationToken,
): Promise<string> {
  const timestamp = Date.now();

  const abortController = new AbortController();
  token.onCancellationRequested(() => {
    abortController.abort();
  });

  try {
    const promise = execFile("zig", ["fmt", "--stdin"], {
      maxBuffer: 10 * 1024 * 1024, // 10MB
      signal: abortController.signal,
      timeout: 60000, // 60 seconds (this is a very high value because 'zig fmt' is just in time compiled)
    });
    promise.child.stdin?.end(text);

    const zigFmtResult = await promise;

    if (zigFmtResult.stdout.length === 0) return text;
    return zigFmtResult.stdout;
  } catch (err) {
    console.error("runZigFmt error:", err.stderr);
    if (token.isCancellationRequested) {
      return text;
    }
    return text;
  } finally {
    fmtStats.increment("zig", Date.now() - timestamp);
  }
}


export interface CancellationToken {
  /**
   * Is `true` when the token has been cancelled, `false` otherwise.
   */
  isCancellationRequested: boolean;

  /**
   * An [event](#Event) which fires upon cancellation.
   */
  onCancellationRequested: (v: () => void) => void;
}


export const fmtStats = {
  zigCount: 0,
  htmlCount: 0,
  count: 0,

  zigTime: null,
  htmlTime: null,
  time: null,
  
  clear() {
    this.zigFmt = 0;
    this.htmlFmt = 0;
    this.fmt = 0;
  },
  increment(type: "zig" | "html" | 'fmt', duration?: number) {
    if (type === 'fmt') this.count++;
    if (type === "zig") this.zigCount++;
    if (type === "html") this.htmlCount++;
    if (duration) {
      if (type === 'zig') this.zigTime = (this.zigTime ?? 0) + duration;
      if (type === 'html') this.htmlTime = (this.htmlTime ?? 0) + duration;
      if (type === 'fmt') this.time = (this.time ?? 0) + duration;
    }
  },
  reset() {
    this.zigCount = 0;
    this.htmlCount = 0;
    this.count = 0;
    this.zigTime = null;
    this.htmlTime = null;
    this.fmtTime = null;
  },
  getStats() {
    return {
      count: {
        zig: this.zigCount,
        html: this.htmlCount,
        total: this.count,
      },
      time: {
        zig: this.zigTime,
        html: this.htmlTime,
        total: this.time,
      },
    };
  },
};
