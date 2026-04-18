import { describe, test, expect } from "bun:test";
import { execSync } from "node:child_process";
import { generateZigFingerprint } from "../bin/index.js";

const ZIG_RUN = "zig run test/fingerprint.zig -- ";
const cwd = import.meta.dirname + "/..";

function zigGenerate(name: string): string {
  return execSync(`${ZIG_RUN} generate ${name}`, { cwd, encoding: "utf8" }).trim();
}

function zigValidate(name: string, hex: string): boolean {
  return execSync(`${ZIG_RUN} validate ${name} ${hex}`, { cwd, encoding: "utf8" }).trim() === "true";
}

describe("fingerprint", () => {
  const names = ["my_app", "ziex_app", "zx", "hello_world", "a"];

  test.each(names)("node fingerprint is valid in zig for '%s'", (name) => {
    const nodeFp = generateZigFingerprint(name);
    expect(zigValidate(name, nodeFp)).toBe(true);
  });

  test.each(names)("zig fingerprint is valid in node for '%s'", (name) => {
    const zigFp = zigGenerate(name);
    const nodeFp = generateZigFingerprint(name);

    // Extract checksum (upper 32 bits) from both - the random id will differ
    const zigChecksum = BigInt(zigFp) >> 32n;
    const nodeChecksum = BigInt(nodeFp) >> 32n;
    expect(nodeChecksum).toBe(zigChecksum);
  });

  test("rejects fingerprint with wrong name", () => {
    const fp = generateZigFingerprint("my_app");
    expect(zigValidate("wrong_name", fp)).toBe(false);
  });
});
