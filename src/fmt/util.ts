import {
  getLanguageService,
  TextDocument,
  TokenType,
} from "vscode-html-languageservice";

export function extractHtml(doc: string) {
  const htmlLanguageService = getLanguageService();
  const htmls: string[] = [];
  const errors: string[] = [];

  // Build a lookup of characters that are inside strings
  const inString = new Array<boolean>(doc.length).fill(false);

  // Track string positions
  let i = 0;
  while (i < doc.length) {
    const char = doc[i];
    if (char === '"' || char === "'") {
      const quoteChar = char;
      const stringStart = i;
      i++; // Skip opening quote
      // Find closing quote (handle escaped quotes)
      while (i < doc.length) {
        if (doc[i] === quoteChar && doc[i - 1] !== "\\") {
          // Mark all characters in this string as inside string
          for (let j = stringStart; j <= i; j++) {
            inString[j] = true;
          }
          i++;
          break;
        }
        i++;
      }
    } else {
      i++;
    }
  }

  // Track parentheses depth - HTML should only be extracted if inside parentheses
  const parenDepth = new Array<number>(doc.length).fill(0);
  let currentDepth = 0;
  for (let i = 0; i < doc.length; i++) {
    const char = doc[i];
    // Only count parentheses outside of strings
    if (!inString[i]) {
      if (char === "(") {
        currentDepth++;
      } else if (char === ")") {
        currentDepth--;
      }
    }
    parenDepth[i] = currentDepth;
  }

  // Use scanner to find HTML tags
  const scanner = htmlLanguageService.createScanner(doc);
  const matches: Array<{
    start: number;
    end: number;
    tagName: string;
    fullMatch: string;
  }> = [];

  // Track opening tags with their positions
  interface TagInfo {
    tagName: string;
    start: number;
    startTagEnd: number; // Position after the opening tag '>'
  }
  const tagStack: TagInfo[] = [];

  let tokenType = scanner.scan();
  while (tokenType !== TokenType.EOS) {
    const offset = scanner.getTokenOffset();

    // Skip tokens inside strings
    if (inString[offset]) {
      tokenType = scanner.scan();
      continue;
    }

    // Only process HTML tags that are inside parentheses (HTML content always has parentheses around it)
    if (parenDepth[offset] === 0) {
      tokenType = scanner.scan();
      continue;
    }

    if (tokenType === TokenType.StartTagOpen) {
      const tagStart = offset; // Position of '<'
      // Scan to get tag name
      tokenType = scanner.scan();
      if (tokenType === TokenType.StartTag) {
        const tagName = scanner.getTokenText().toLowerCase();

        // Continue scanning until we find the closing '>' or '/>'
        let startTagEnd = -1;
        while (
          tokenType !== TokenType.EOS &&
          tokenType !== TokenType.StartTagClose &&
          tokenType !== TokenType.StartTagSelfClose
        ) {
          tokenType = scanner.scan();
        }

        if (
          tokenType === TokenType.StartTagClose ||
          tokenType === TokenType.StartTagSelfClose
        ) {
          startTagEnd = scanner.getTokenEnd(); // Position after '>' or '/>'

          // Only track if it's not self-closing
          if (tokenType === TokenType.StartTagClose) {
            tagStack.push({
              tagName,
              start: tagStart,
              startTagEnd: startTagEnd,
            });
          }
        }
      }
    } else if (tokenType === TokenType.EndTagOpen) {
      const endTagStart = offset; // Position of '</'
      // Scan to get tag name
      tokenType = scanner.scan();
      if (tokenType === TokenType.EndTag) {
        const tagName = scanner.getTokenText().toLowerCase();

        // Continue scanning until we find the closing '>'
        while (
          tokenType !== TokenType.EOS &&
          tokenType !== TokenType.EndTagClose
        ) {
          tokenType = scanner.scan();
        }

        if (tokenType === TokenType.EndTagClose) {
          const tagEnd = scanner.getTokenEnd(); // Position after '>'

          // Find matching opening tag (most recent one with same name)
          let foundMatch = false;
          for (let i = tagStack.length - 1; i >= 0; i--) {
            const openTag = tagStack[i];
            if (openTag.tagName === tagName) {
              // Found matching opening tag
              const htmlContent = doc.substring(openTag.start, tagEnd);
              matches.push({
                start: openTag.start,
                end: tagEnd,
                tagName: tagName,
                fullMatch: htmlContent,
              });

              // Remove only the matching tag from stack
              // Tags opened after this one will remain and be detected as errors
              tagStack.splice(i, 1);
              foundMatch = true;
              break;
            }
          }

          if (!foundMatch) {
            // No matching opening tag found - this is an error
            errors.push(
              `Closing tag </${tagName}> at position ${endTagStart} has no matching opening tag`,
            );
          }
        }
      }
    }

    tokenType = scanner.scan();
  }

  // Check for unclosed opening tags
  for (const openTag of tagStack) {
    errors.push(
      `Opening tag <${openTag.tagName}> at position ${openTag.start} has no closing tag`,
    );
  }

  // Filter out nested matches - only keep outermost HTML blocks
  const filteredMatches: Array<{
    start: number;
    end: number;
    tagName: string;
    fullMatch: string;
  }> = [];
  for (let i = 0; i < matches.length; i++) {
    const current = matches[i];
    let isNested = false;

    // Check if this match is nested inside any other match
    for (let j = 0; j < matches.length; j++) {
      if (i !== j) {
        const other = matches[j];
        if (current.start > other.start && current.end < other.end) {
          isNested = true;
          break;
        }
      }
    }

    if (!isNested) {
      filteredMatches.push(current);
    }
  }

  // Sort matches by start position
  filteredMatches.sort((a, b) => a.start - b.start);

  // Process each HTML block with the language service
  for (let i = 0; i < filteredMatches.length; i++) {
    const match = filteredMatches[i];
    const htmlContent = match.fullMatch;

    // Create a TextDocument for this HTML block
    const htmlDoc = TextDocument.create(
      `untitled:html-block-${i}`,
      "html",
      1,
      htmlContent,
    );

    // Parse the HTML document
    const htmlDocument = htmlLanguageService.parseHTMLDocument(htmlDoc);

    // Check for unclosed tags by examining the parsed document
    // Void elements (self-closing tags) that don't need closing tags
    const voidElements = new Set([
      "area",
      "base",
      "br",
      "col",
      "embed",
      "hr",
      "img",
      "input",
      "link",
      "meta",
      "param",
      "source",
      "track",
      "wbr",
    ]);

    const checkUnclosedTags = (node: any): void => {
      if (node.tag) {
        const tagName = node.tag.toLowerCase();
        // Check if this tag has a closing tag
        // endTagStart is undefined if the tag is not closed
        if (node.endTagStart === undefined && !voidElements.has(tagName)) {
          errors.push(
            `Tag <${node.tag}> is not closed in HTML block ${i} (root: <${match.tagName}>)`,
          );
        }
      }
      if (node.children) {
        for (const child of node.children) {
          checkUnclosedTags(child);
        }
      }
    };

    for (const root of htmlDocument.roots) {
      checkUnclosedTags(root);
    }

    htmls.push(htmlContent);
  }

  return {
    htmls,
    errors,
    len: htmls.length,
  };
}

/**
 * Expression type definitions with regex patterns for detection.
 * Includes both expression patterns (if/for/while/switch/else) and block patterns (if_block/for_block/etc).
 */
export const expressionTypes: Array<{ keyword: string; regex: RegExp }> = [
  { keyword: "if", regex: /\bif\s*\(/g },
  { keyword: "for", regex: /\bfor\s*\(/g },
  { keyword: "while", regex: /\bwhile\s*\(/g },
  { keyword: "else", regex: /\belse\s*{/g },
  { keyword: "switch", regex: /\bswitch\s*\(/g },
  { keyword: "if_block", regex: /\bif\s*\(/g },
  { keyword: "else_block", regex: /\belse\s*{/g },
  { keyword: "for_block", regex: /\bfor\s*\(/g },
  { keyword: "while_block", regex: /\bwhile\s*\(/g },
  { keyword: "switch_block", regex: /\bswitch\s*\(/g },
];

/**
 * Detects the expression type at a given position in text by looking backwards.
 * Returns the closest expression type and whether it's a block (has opening brace after condition).
 * @param text The text to search in
 * @param position The position to check from
 * @returns The expression type keyword or null if not found
 */
export function detectExprType(
  text: string,
  position: number,
): { keyword: string; isBlock: boolean } | null {
  const beforeText = text.slice(0, position);
  const matches: Array<{ keyword: string; index: number; isBlock: boolean }> =
    [];

  // Check for block patterns first (more specific)
  for (const { keyword } of expressionTypes) {
    if (!keyword.endsWith("_block")) continue;

    const baseKeyword = keyword.replace("_block", "");
    // For block patterns, we need to find the keyword, then check if there's a brace after the condition
    const regex = new RegExp(`\\b${baseKeyword}\\s*\\(`, "g");
    let m;
    while ((m = regex.exec(beforeText)) !== null) {
      // Find the closing paren of the condition
      const afterKeyword = m.index + m[0].length - 1; // Position of opening '('
      const conditionEnd = findParen(beforeText, afterKeyword);
      if (conditionEnd === -1) continue;

      // Skip whitespace after condition
      let pos = conditionEnd + 1;
      while (pos < beforeText.length && /\s/.test(beforeText[pos])) {
        pos++;
      }

      // Check if there's an opening brace after the condition (indicating a block)
      if (pos < beforeText.length && beforeText[pos] === "{") {
        matches.push({ keyword, index: m.index, isBlock: true });
      }
    }
  }

  // Check for expression patterns (less specific, but catch all)
  for (const { keyword } of expressionTypes) {
    if (keyword.endsWith("_block")) continue;

    const regex = new RegExp(
      `\\b${keyword}\\s*${keyword === "else" ? "{" : "\\("}`,
      "g",
    );
    let m;
    while ((m = regex.exec(beforeText)) !== null) {
      // For else, it's always a block pattern
      const isBlock = keyword === "else";
      matches.push({ keyword, index: m.index, isBlock });
    }
  }

  if (matches.length === 0) {
    return null;
  }

  // Sort by index descending to get the closest (last) one
  matches.sort((a, b) => b.index - a.index);
  const closest = matches[0];

  // Determine if it's actually a block by checking the pattern
  if (!closest.isBlock && closest.keyword !== "else") {
    // Check if there's a brace after the condition
    const regex = new RegExp(`\\b${closest.keyword}\\s*\\(`, "g");
    const m = regex.exec(beforeText.slice(closest.index));
    if (m) {
      const afterKeyword = closest.index + m.index + m[0].length - 1;
      const conditionEnd = findParen(beforeText, afterKeyword);
      if (conditionEnd !== -1) {
        let pos = conditionEnd + 1;
        while (pos < beforeText.length && /\s/.test(beforeText[pos])) {
          pos++;
        }
        if (pos < beforeText.length && beforeText[pos] === "{") {
          closest.isBlock = true;
          closest.keyword = `${closest.keyword}_block`;
        }
      }
    }
  }

  return { keyword: closest.keyword, isBlock: closest.isBlock };
}

export function findParen(text: string, startPos: number): number {
  let depth = 0;
  let pos = startPos;
  let inString = false;
  let stringChar = "";

  while (pos < text.length) {
    const char = text[pos];
    const prevChar = pos > 0 ? text[pos - 1] : "";

    // Handle string literals
    if (!inString && (char === '"' || char === "'")) {
      inString = true;
      stringChar = char;
      pos++;
      continue;
    }

    if (inString) {
      if (char === stringChar && prevChar !== "\\") {
        inString = false;
      }
      pos++;
      continue;
    }

    // Handle parentheses
    if (char === "(") {
      depth++;
    } else if (char === ")") {
      depth--;
      if (depth === 0) {
        return pos + 1;
      }
    }

    pos++;
  }

  return -1;
}

/**
 * Removes indentation from specific lines in an array of lines.
 * Used to adjust indentation after merging braces in Zig expressions.
 */
export function indentNegate(
  lines: string[],
  startLine: number,
  endLine: number,
  negateLevel: number,
  tabSize: number,
  insertSpaces: boolean,
): string[] {
  const indentSize = insertSpaces ? tabSize : 1;
  const indentToRemove = " ".repeat(indentSize * negateLevel);

  return lines.map((line, index) => {
    if (index >= startLine && index <= endLine) {
      // Remove the specified level of indentation
      if (line.startsWith(indentToRemove)) {
        return line.slice(indentToRemove.length);
      }
      // If using tabs, try removing tabs
      if (!insertSpaces && line.startsWith("\t")) {
        return line.slice(negateLevel);
      }
    }
    return line;
  });
}

/**
 * Removes semicolons that were added after @html(n) patterns.
 * This reverses the effect of addSemicolonsToHtmlPlaceholders.
 */
export function removeSemiFromHtml(text: string): string {
  // Remove semicolons that immediately follow @html(n) or (@html(n))
  return text.replace(/(@html\(\d+\)|\(@html\(\d+\)\));/g, "$1");
}

/**
 * Removes semicolons that were added after complete expression statements.
 * This reverses the effect of addSemicolonsToCompleteExpressions.
 */
export function removeSemiFromExpr(text: string): string {
  type ExpressionType = "if" | "for" | "switch" | "while";

  const expressionKeywords: ExpressionType[] = ["if", "for", "switch", "while"];
  const matches: Array<{ start: number; end: number; type: ExpressionType }> =
    [];

  // Find all expression keywords (same logic as addSemicolonsToCompleteExpressions)
  for (const keyword of expressionKeywords) {
    const regex = new RegExp(`\\b${keyword}\\s*\\(`, "g");
    let match;
    while ((match = regex.exec(text)) !== null) {
      const start = match.index;
      const afterKeyword = match.index + match[0].length - 1;

      const conditionEnd = findParen(text, afterKeyword);
      if (conditionEnd === -1) continue;

      let pos = conditionEnd;
      while (pos < text.length && /\s/.test(text[pos])) {
        pos++;
      }

      if (text[pos] === "|") {
        pos++;
        const captureEnd = text.indexOf("|", pos);
        if (captureEnd !== -1) {
          pos = captureEnd + 1;
          while (pos < text.length && /\s/.test(text[pos])) {
            pos++;
          }
        }
      }

      if (text[pos] === "(") {
        const bodyEnd = findParen(text, pos);
        if (bodyEnd === -1) continue;

        let end = bodyEnd;

        if (keyword === "if") {
          let elsePos = bodyEnd;
          while (elsePos < text.length && /\s/.test(text[elsePos])) {
            elsePos++;
          }

          if (text.substring(elsePos, elsePos + 4) === "else") {
            elsePos += 4;
            while (elsePos < text.length && /\s/.test(text[elsePos])) {
              elsePos++;
            }

            if (text[elsePos] === "(") {
              const elseBodyEnd = findParen(text, elsePos);
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

  // Remove semicolons from matches (process from end to start)
  let result = text;
  for (let i = matches.length - 1; i >= 0; i--) {
    const { end, type } = matches[i];

    // Skip switch statements (they don't have semicolons)
    if (type === "switch") {
      continue;
    }

    // Check if there's a semicolon after the expression (with optional whitespace)
    const afterMatch = result.slice(end);
    const trimmedAfter = afterMatch.trimStart();

    if (trimmedAfter.startsWith(";")) {
      // Find the actual position of the semicolon (accounting for whitespace)
      const semicolonPos = end + (afterMatch.length - trimmedAfter.length);
      // Remove the semicolon
      result = result.slice(0, semicolonPos) + result.slice(semicolonPos + 1);
    }
  }

  return result;
}
