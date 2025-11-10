import { test, expect, describe } from "bun:test";
import {
  extractHtmls,
  cleanupZigExprs,
  extractZigExprs as prepareFmtSegment,
  addSemicolonsToCompleteExpressions,
  addSemicolonsToHtmlPlaceholders,
} from "../../src/fmt/fmt";
import * as fmtUtil from "../../src/fmt/util";
import {
  findBalancedParens,
  indentNegate,
  removeSemicolonsFromHtmlPlaceholders,
  removeSemicolonsFromCompleteExpressions,
} from "../../src/fmt/util";
import { outLargeMixedContent } from "../data.test";

test("prefareFmtDoc", () => {
  const testableHtmls = documentHtmls.slice(0, 2);
  const preparedDoc = extractHtmls(documentText);

  expect(preparedDoc.preparedDocumentText).toEqual(expectedDocumentText);
  expect(preparedDoc.htmlContents.size).toEqual(testableHtmls.length);
  testableHtmls.forEach((html, index) => {
    expect(preparedDoc.htmlContents.get(`@html(${index})`)).toEqual(html);
  });
});

describe("addSemicolonsToCompleteExpressions", () => {
  const evalar = (input: string) => addSemicolonsToCompleteExpressions(addSemicolonsToHtmlPlaceholders(input));
  test("semi after for expression", () => {
    expect(evalar(`test {for (posts) |post| {@html(0)}}`))
      .toEqual(`test {for (posts) |post| {@html(0);}}`);

  });

  test("semi after paren", () => {
    expect(evalar(`test {for (posts) |post| {(@html(0))}}`))
      .toEqual(`test {for (posts) |post| {(@html(0));}}`);

  });

  test("seme after paren whitespace/line breaks", () => {
    const evalar = (input: string) => addSemicolonsToCompleteExpressions(addSemicolonsToHtmlPlaceholders(input));
    expect(evalar(`test {for (posts)          |post| {(\n                @html(0)            \n)}}`))
      .toEqual(`test {for (posts)          |post| {(\n                @html(0)            \n);}}`);
  });
});

describe("extractHtmls", () => {
  test("make sure large mixed content correctly extracted", () => {
    const html = fmtUtil.extractHtmls(outLargeMixedContent);
    expect(html.htmls.length).toEqual(2);
  })

  test("html inside string should be ignored", () => {
    const doc = `
    pub fn Page(allocator: zx.Allocator) zx.Component {
    const user_name = "Alice & Bob";
    const html_content = "<script>alert('XSS')</script>";
    const unsafe_html = "<span>Test</span>";

    return (
        <main @allocator={allocator}>
            <section>
                <p>User: {user_name}</p>
                <p>Safe HTML: {html_content}</p>
                <p>Unsafe HTML: {[unsafe_html:s]}</p>
            </section>
        </main>
    );
}

const zx = @import("zx");

    `;
    const html = fmtUtil.extractHtmls(doc);
    expect(html.htmls.length).toEqual(1);
  })
});

const documentHtmls = [
  `<nav>
        {for (navs) |nav| (
            <a href={nav.href}>{nav.text}</a>
        )}
    </nav>`,
  `<div>
        {if (isDev) (
            <a href="https://nuhu.dev">Dev</a>
        )}
    </div>`,
  `<div>
        <div>
            {if (isDev) (
                <a href="https://nuhu.dev">Dev</a>
            )}
        </div>
        <div>   
            {for (navs) |nav| (
                <a href={nav.href}>{nav.text}</a>
            )}
        </div>
        <div>
            {switch (isDev) (
                case true:
                    <a href="https://nuhu.dev">Dev</a>
                case false:
                    <a href="https://nuhu.dev">Not Dev</a>
            )}
        </div>
    </div>`,
];
const documentHtmlsExprCount = [1, 1, 3];

const documentText = `
pub fn Navbar(allocator: zx.Allocator) zx.Component {
    return (
        ${documentHtmls[0]}
    );
}

pub fn NavItem(allocator: zx.Allocator, href: string, text: string) zx.Component {
    return (
        ${documentHtmls[1]}
    );
}

const zx = @import("zx");
`;

const expectedDocumentText = `
pub fn Navbar(allocator: zx.Allocator) zx.Component {
    return (
        @html(0)
    );
}

pub fn NavItem(allocator: zx.Allocator, href: string, text: string) zx.Component {
    return (
        @html(1)
    );
}

const zx = @import("zx");
`;

const expectedZigSegments = [1, 1, 2, 1];
test("prepareFmtSegment", () => {
  documentHtmls.forEach((html, index) => {
    const preparedDoc = prepareFmtSegment(html);
    // Log for debugging
    // console.log(
    //   `prepareFmtSegment for index=${index} htmlExprCount=${documentHtmlsExprCount[index]}`,
    // );
    // console.log("zigSegments keys:", Array.from(preparedDoc.exprss.keys()));
    expect(preparedDoc.exprss.size).toEqual(documentHtmlsExprCount[index]);

    preparedDoc.exprss.forEach((zigSegment, key) => {
      // console.log("--- zigSegment key:", key);
      // console.log(zigSegment);
      const preparedSubSeg = extractHtmls(zigSegment);
      // console.log(
      //   "preparedSubSeg.htmlContents keys:",
      //   Array.from(preparedSubSeg.htmlContents.keys()),
      // );
      // expect(preparedSubSeg.htmlContents.size).toEqual(expectedZigSegments[index]);
      // expect(preparedSubSeg.htmlContents.get(`@html(0)`)).toEqual("<a href={nav.href}>{nav.text}</a>");
    });
  });
});

test("prepareFmtSegment supports whitespace after brace", () => {
  const variants = [
    {
      text: `{ for (items) |item| ( <a>{item}</a> ) }`,
      contains: "for (items)",
    },
    {
      text: `{
for (items) |item| ( <a>{item}</a> ) }`,
      contains: "for (items)",
    },
    { text: `{   if (cond) ( <span>Ok</span> ) }`, contains: "if (cond)" },
    {
      text: `{
   switch (cond) ( case true: <b>Yes</b> case false: <b>No</b> ) }`,
      contains: "switch (cond)",
    },
  ];

  variants.forEach((variant, i) => {
    const prepared = prepareFmtSegment(variant.text);
    expect(prepared.exprss.size).toBe(1);
    const [key, value] = Array.from(prepared.exprss.entries())[0];
    expect(value).toContain(variant.contains);
    // Ensure replacement occurred
    expect(prepared.preparedSegmentText).toContain(key);
  });
});

test("transformZigExpression removes extra line breaks and adjusts indentation", () => {
  const input = `{
    switch (user_swtc.user_type) {
        .admin => ("Admin"),
        .member => ("Member"),
    }
}`;

  const expectedOutput = `{switch (user_swtc.user_type) {
    .admin => ("Admin"),
    .member => ("Member"),
}}`;

  const output = cleanupZigExprs(input, 4, true);
  expect(output).toEqual(expectedOutput);
});

test("transformZigExpression merges consecutive closing braces", () => {
  const input = `{
    switch (user_swtc.user_type) {
        .admin => (<p>Powerful</p>),
        .member => (<p>Powerless</p>),
    }
}`;

  const expectedOutput = `{switch (user_swtc.user_type) {
    .admin => (<p>Powerful</p>),
    .member => (<p>Powerless</p>),
}}`;

  const output = cleanupZigExprs(input, 4, true);
  expect(output).toEqual(expectedOutput);
  // Ensure closing braces are on the same line
  expect(output).toContain("}}");
  expect(output.split("}}").length).toBe(2); // Should only have one occurrence of }}
  // Additional checks for formatting
  const lines = output.split("\n");
  // Ensure no line contains only a single closing brace
  lines.forEach((line) => {
    expect(line.trim()).not.toBe("}");
  });
  // Optionally, check the total line count matches expected output
  expect(lines.length).toBe(expectedOutput.split("\n").length);
});

test("transformZigExpression handles indented closing braces", () => {
  // Simulating what might come from the formatter with indentation
  const input = `    switch (user_swtc.user_type) {
        .admin => (<p>Powerful</p>),
        .member => (<p>Powerless</p>),
    }
}`;

  const output = cleanupZigExprs(input, 4, true);
  // console.log("Output:", JSON.stringify(output));
  // Should merge the closing braces
  expect(output).toContain("}}");
  // Should not have } on a separate line
  const lines = output.split("\n");
  const lastLine = lines[lines.length - 1];
  expect(lastLine.trim()).toMatch(/^}+$/);
});

describe("findBalancedParens", () => {
  test("finds simple balanced parentheses", () => {
    const text = "if (condition) (value)";
    const result = findBalancedParens(text, 3); // Start at '(' after 'if '
    expect(result).toBe(14); // Position after ')'
  });

  test("finds nested parentheses", () => {
    const text = "if ((a && b) || c) (value)";
    const result = findBalancedParens(text, 3); // Start at first '('
    expect(result).toBe(18); // Position after closing ')'
  });

  test("handles parentheses inside strings", () => {
    const text = 'if (name == "test()") (value)';
    const result = findBalancedParens(text, 3); // Start at '(' after 'if '
    expect(result).toBe(21); // Position after closing ')', skipping parens in string
  });

  test("handles escaped quotes in strings", () => {
    const text = 'if (name == "test\\"()") (value)';
    const result = findBalancedParens(text, 3);
    expect(result).toBe(23); // Position after closing ')'
  });

  test("returns -1 for unbalanced parentheses", () => {
    const text = "if (condition (value)";
    const result = findBalancedParens(text, 3);
    expect(result).toBe(-1);
  });

  test("handles empty parentheses", () => {
    const text = "if () (value)";
    const result = findBalancedParens(text, 3);
    expect(result).toBe(5); // Position after ')'
  });
});

describe("indentNegate", () => {
  test("removes one level of indentation from specified lines", () => {
    const lines = [
      "    first line",
      "        second line",
      "        third line",
      "    fourth line",
    ];
    const result = indentNegate(lines, 1, 2, 1, 4, true);
    expect(result).toEqual([
      "    first line",
      "    second line",
      "    third line",
      "    fourth line",
    ]);
  });

  test("removes multiple levels of indentation", () => {
    const lines = [
      "        first line",
      "            second line",
      "            third line",
    ];
    const result = indentNegate(lines, 1, 2, 2, 4, true);
    expect(result).toEqual([
      "        first line",
      "    second line",
      "    third line",
    ]);
  });

  test("handles tabs instead of spaces", () => {
    const lines = [
      "\tfirst line",
      "\t\tsecond line",
      "\t\tthird line",
    ];
    const result = indentNegate(lines, 1, 2, 1, 4, false);
    expect(result).toEqual([
      "\tfirst line",
      "\tsecond line",
      "\tthird line",
    ]);
  });

  test("does not modify lines outside range", () => {
    const lines = [
      "    first line",
      "        second line",
      "        third line",
      "    fourth line",
    ];
    const result = indentNegate(lines, 1, 1, 1, 4, true);
    expect(result).toEqual([
      "    first line",
      "    second line",
      "        third line",
      "    fourth line",
    ]);
  });

  test("handles lines without enough indentation", () => {
    const lines = [
      "    first line",
      "  second line", // Only 2 spaces, trying to remove 4
      "        third line",
    ];
    const result = indentNegate(lines, 1, 1, 1, 4, true);
    expect(result).toEqual([
      "    first line",
      "  second line", // Unchanged
      "        third line",
    ]);
  });
});

describe("removeSemicolonsFromHtmlPlaceholders", () => {
  test("removes semicolon after @html(n)", () => {
    const input = "test @html(0);";
    const result = removeSemicolonsFromHtmlPlaceholders(input);
    expect(result).toBe("test @html(0)");
  });

  test("removes semicolon after (@html(n))", () => {
    const input = "test (@html(0));";
    const result = removeSemicolonsFromHtmlPlaceholders(input);
    expect(result).toBe("test (@html(0))");
  });

  test("removes multiple semicolons", () => {
    const input = "@html(0); @html(1); (@html(2));";
    const result = removeSemicolonsFromHtmlPlaceholders(input);
    expect(result).toBe("@html(0) @html(1) (@html(2))");
  });

  test("does not remove semicolons that are not immediately after placeholders", () => {
    const input = "@html(0) ; test;";
    const result = removeSemicolonsFromHtmlPlaceholders(input);
    expect(result).toBe("@html(0) ; test;");
  });

  test("handles placeholders without semicolons", () => {
    const input = "@html(0) @html(1)";
    const result = removeSemicolonsFromHtmlPlaceholders(input);
    expect(result).toBe("@html(0) @html(1)");
  });
});

describe("removeSemicolonsFromCompleteExpressions", () => {
  test("removes semicolon after if expression", () => {
    const input = "if (condition) (value);";
    const result = removeSemicolonsFromCompleteExpressions(input);
    expect(result).toBe("if (condition) (value)");
  });

  test("removes semicolon after for expression", () => {
    const input = "for (items) |item| (value);";
    const result = removeSemicolonsFromCompleteExpressions(input);
    expect(result).toBe("for (items) |item| (value)");
  });

  test("removes semicolon after if-else expression", () => {
    const input = "if (condition) (value1) else (value2);";
    const result = removeSemicolonsFromCompleteExpressions(input);
    expect(result).toBe("if (condition) (value1) else (value2)");
  });

  test("does not remove semicolon after switch expression", () => {
    const input = "switch (value) (case 1: (a) case 2: (b));";
    const result = removeSemicolonsFromCompleteExpressions(input);
    // Switch statements don't have semicolons, so it should remain unchanged
    expect(result).toBe("switch (value) (case 1: (a) case 2: (b));");
  });

  test("removes semicolon with whitespace", () => {
    const input = "if (condition) (value)   ;";
    const result = removeSemicolonsFromCompleteExpressions(input);
    expect(result).toBe("if (condition) (value)   ");
  });

  test("handles multiple expressions", () => {
    const input = "if (a) (1); for (items) (2); while (b) (3);";
    const result = removeSemicolonsFromCompleteExpressions(input);
    expect(result).toBe("if (a) (1) for (items) (2) while (b) (3)");
  });

  test("does not remove semicolons that are not after complete expressions", () => {
    const input = "if (condition) (value); other code;";
    const result = removeSemicolonsFromCompleteExpressions(input);
    expect(result).toBe("if (condition) (value) other code;");
  });
});
