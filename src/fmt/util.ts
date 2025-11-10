import { getLanguageService, TextDocument, TokenType } from "vscode-html-languageservice";

export function extractHtmls(doc: string) {
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
                if (doc[i] === quoteChar && doc[i - 1] !== '\\') {
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
            if (char === '(') {
                currentDepth++;
            } else if (char === ')') {
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
                while (tokenType !== TokenType.EOS && tokenType !== TokenType.StartTagClose && tokenType !== TokenType.StartTagSelfClose) {
                    tokenType = scanner.scan();
                }
                
                if (tokenType === TokenType.StartTagClose || tokenType === TokenType.StartTagSelfClose) {
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
                while (tokenType !== TokenType.EOS && tokenType !== TokenType.EndTagClose) {
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
                        errors.push(`Closing tag </${tagName}> at position ${endTagStart} has no matching opening tag`);
                    }
                }
            }
        }

        tokenType = scanner.scan();
    }

    // Check for unclosed opening tags
    for (const openTag of tagStack) {
        errors.push(`Opening tag <${openTag.tagName}> at position ${openTag.start} has no closing tag`);
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
            htmlContent
        );

        // Parse the HTML document
        const htmlDocument = htmlLanguageService.parseHTMLDocument(htmlDoc);

        // Check for unclosed tags by examining the parsed document
        // Void elements (self-closing tags) that don't need closing tags
        const voidElements = new Set([
            'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
            'link', 'meta', 'param', 'source', 'track', 'wbr'
        ]);

        const checkUnclosedTags = (node: any): void => {
            if (node.tag) {
                const tagName = node.tag.toLowerCase();
                // Check if this tag has a closing tag
                // endTagStart is undefined if the tag is not closed
                if (node.endTagStart === undefined && !voidElements.has(tagName)) {
                    errors.push(`Tag <${node.tag}> is not closed in HTML block ${i} (root: <${match.tagName}>)`);
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
