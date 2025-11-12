import { test, expect, describe, afterAll } from "bun:test";
import { formatZx, fmtStats, preCompileZigFmt } from "../../src/fmt/fmt";
import { fmtCases } from "../data.test";
import Bun from "bun";

const virtualHtmlDocumentContents = new Map<string, string>();

describe("fmt", () => {
  const cancellationTokenSource = new CancellationTokenSource();
  preCompileZigFmt();
  for (const fmtCase of fmtCases) {
    Object.keys(fmtCase)
      .filter((key) => key !== "ins")
      .forEach((key) => {
        for (
          let inputIndex = 0;
          inputIndex < fmtCase.ins.length;
          inputIndex++
        ) {
          const inputText = fmtCase.ins[inputIndex];
          test(`ZX Expr - ${key.slice("out".length)} #${inputIndex}`, async () => {
            const outputText = await formatZx(
              inputText,
              cancellationTokenSource.token,
              "test.zig",
              virtualHtmlDocumentContents,
            );
            await log(inputText, outputText);
            // @ts-ignore
            expect(outputText).toEqual(fmtCase[key]);

            // reformat the output text
            // const reformattedOutputText = await formatZx(
            //   outputText,
            //   cancellationTokenSource.token,
            //   "test.zx",
            //   virtualHtmlDocumentContents,
            // );
            // expect(reformattedOutputText).toEqual(outputText);

            // await log(inputText, reformattedOutputText);
          });
        }
      });
  }

  cancellationTokenSource.cancel();
});

afterAll(() => {
  console.debug(fmtStats.getStats());
  fmtStats.clear();
});

async function log(input: string, output: string) {
  const inputFile = Bun.file("test/logs/input.zx");
  const outputFile = Bun.file("test/logs/output.zx");
  await inputFile.write(input);
  await outputFile.write(output);

  const logFile = Bun.file("test/logs/fmt.zx");
  const existing = (await logFile.exists()) ? await logFile.text() : "";
  const newLog = `${existing}${input}
//--->>
${output}
//-------------------------------------------------------------
`;
  await Bun.write("test/logs/fmt.zx", newLog);
}

class CancellationTokenSource {
  queue: (() => void)[] = [];
  token = {
    isCancellationRequested: false,
    onCancellationRequested: (callback: () => void) => {
      this.queue.push(callback);
    },
  };
  cancel() {
    this.token.isCancellationRequested = true;
    this.queue.forEach((callback) => callback());
    this.queue = [];
  }
  dispose() {}
}
