import { test, expect } from "bun:test";
import {
  extractHtmls,
  cleanupZigExprs,
  extractZigExprs as prepareFmtSegment,
} from "../src/fmt";

test("prefareFmtDoc", () => {
  const testableHtmls = documentHtmls.slice(0, 2);
  const preparedDoc = extractHtmls(documentText);

  // Log the prepared document for inspection
  // console.log(
  //   "prepareFmtDoc.preparedDocumentText:\n",
  //   preparedDoc.preparedDocumentText,
  // );
  // console.log(
  //   "prepareFmtDoc.htmlContents keys:",
  //   Array.from(preparedDoc.htmlContents.keys()),
  // );

  expect(preparedDoc.preparedDocumentText).toEqual(expectedDocumentText);
  expect(preparedDoc.htmlContents.size).toEqual(testableHtmls.length);
  testableHtmls.forEach((html, index) => {
    expect(preparedDoc.htmlContents.get(`@html(${index})`)).toEqual(html);
  });
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
    return (@html(0));
}

pub fn NavItem(allocator: zx.Allocator, href: string, text: string) zx.Component {
    return (@html(1));
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
