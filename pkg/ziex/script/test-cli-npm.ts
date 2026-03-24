import { $ } from "bun";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

/**
 * End-to-end test for the ziex CLI npm package using verdaccio.
 *
 * Requires `bun run script/build-cli.ts` to have been run first.
 *
 * This script:
 * 1. Starts a local verdaccio registry
 * 2. Publishes the real dist-cli packages to verdaccio
 * 3. Installs ziex globally via npm from verdaccio
 * 4. Verifies `ziex version` and `zx version` work
 * 5. Cleans up (unless --keep-running is passed)
 *
 * Flags:
 *   --keep-running  Keep verdaccio running after tests for manual testing
 */

const ROOT_DIR = join(import.meta.dir, "..");
const DIST_CLI_DIR = join(ROOT_DIR, "dist-cli");
const REGISTRY = "http://localhost:4873";
const KEEP_RUNNING = process.argv.includes("--keep-running");

const PLATFORM_MAP: Record<string, Record<string, { npm: string; distDir: string }>> = {
  darwin: {
    arm64: { npm: "@ziex/cli-darwin-arm64", distDir: "@ziex-cli-darwin-arm64" },
    x64: { npm: "@ziex/cli-darwin-x64", distDir: "@ziex-cli-darwin-x64" },
  },
  linux: {
    x64: { npm: "@ziex/cli-linux-x64", distDir: "@ziex-cli-linux-x64" },
    arm64: { npm: "@ziex/cli-linux-arm64", distDir: "@ziex-cli-linux-arm64" },
  },
  win32: {
    x64: { npm: "@ziex/cli-win32-x64", distDir: "@ziex-cli-win32-x64" },
    arm64: { npm: "@ziex/cli-win32-arm64", distDir: "@ziex-cli-win32-arm64" },
  },
};

async function main() {
  const platform = PLATFORM_MAP[process.platform]?.[process.arch];
  if (!platform) {
    console.error(`Unsupported platform: ${process.platform}-${process.arch}`);
    process.exit(1);
  }

  // Verify dist-cli has been built
  const platformPkgDir = join(DIST_CLI_DIR, platform.distDir);
  const mainPkgDir = join(DIST_CLI_DIR, "ziex");

  if (!existsSync(platformPkgDir) || !existsSync(mainPkgDir)) {
    console.error("dist-cli not found. Run `bun run script/build-cli.ts` first.");
    process.exit(1);
  }

  const mainPkgJson = JSON.parse(readFileSync(join(mainPkgDir, "package.json"), "utf-8"));
  const VERSION = mainPkgJson.version;

  console.log(`Testing CLI packages v${VERSION} from dist-cli/`);
  console.log(`Platform: ${platform.npm}`);

  // Step 1: Set up verdaccio
  console.log("\n1. Setting up verdaccio...");
  const testDir = join(tmpdir(), `ziex-cli-test-${Date.now()}`);
  mkdirSync(testDir, { recursive: true });

  const verdaccioConfig = join(testDir, "verdaccio-config.yaml");
  const verdaccioStorage = join(testDir, "verdaccio-storage");
  mkdirSync(verdaccioStorage, { recursive: true });

  writeFileSync(
    verdaccioConfig,
    `storage: ${verdaccioStorage}
auth:
  htpasswd:
    file: ${join(testDir, "htpasswd")}
    max_users: 100
uplinks: {}
packages:
  '@ziex/*':
    access: $anonymous
    publish: $anonymous
  'ziex':
    access: $anonymous
    publish: $anonymous
  '**':
    access: $anonymous
    publish: $anonymous
log: { type: stdout, format: pretty, level: warn }
`,
  );

  try {
    await $`which verdaccio`.quiet();
  } catch {
    console.log("Installing verdaccio...");
    await $`bun install -g verdaccio`.quiet();
  }

  const verdaccioProc = Bun.spawn(["verdaccio", "--config", verdaccioConfig, "--listen", "4873"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  console.log("Waiting for verdaccio to start...");
  let retries = 20;
  while (retries > 0) {
    try {
      await $`curl -s ${REGISTRY}/-/ping`.quiet();
      break;
    } catch {
      retries--;
      await Bun.sleep(500);
    }
  }
  if (retries === 0) {
    console.error("Failed to start verdaccio");
    verdaccioProc.kill();
    process.exit(1);
  }
  console.log("Verdaccio is running!");

  const npmrcContent = `//localhost:4873/:_authToken=fake-token\nregistry=${REGISTRY}\n`;

  try {
    // Step 2: Publish packages from dist-cli
    console.log("\n2. Publishing packages to verdaccio...");

    // Write .npmrc into each package dir for auth
    writeFileSync(join(platformPkgDir, ".npmrc"), npmrcContent);
    writeFileSync(join(mainPkgDir, ".npmrc"), npmrcContent);

    await $`cd ${platformPkgDir} && npm publish --registry ${REGISTRY} --tag test`;
    console.log(`  Published ${platform.npm}@${VERSION}`);

    await $`cd ${mainPkgDir} && npm publish --registry ${REGISTRY} --tag test`;
    console.log(`  Published ziex@${VERSION}`);

    // Step 3: Test global install
    console.log("\n3. Testing global install...");
    const installTestDir = join(testDir, "install-test");
    mkdirSync(installTestDir, { recursive: true });
    writeFileSync(join(installTestDir, ".npmrc"), npmrcContent);

    console.log("  Installing ziex globally with npm...");
    await $`cd ${installTestDir} && npm install -g ziex@${VERSION} --registry ${REGISTRY}`;

    console.log("\n  Running: ziex version");
    const ziexResult = await $`ziex version`.nothrow().text();
    console.log(`  Output: ${ziexResult.trim()}`);

    console.log("\n  Running: zx version");
    const zxResult = await $`zx version`.nothrow().text();
    console.log(`  Output: ${zxResult.trim()}`);

    const passed = ziexResult.trim().length > 0 && zxResult.trim().length > 0;
    console.log(`\n  RESULT: ${passed ? "PASSED" : "FAILED"}`);

    // Step 4: Test npx
    console.log("\n4. Testing npx ziex version...");
    try {
      const npxResult = await $`cd ${installTestDir} && npx --yes --registry ${REGISTRY} ziex@${VERSION} version`.nothrow().text();
      console.log(`  Output: ${npxResult.trim()}`);
      console.log(`  npx test - ${npxResult.trim().length > 0 ? "PASSED" : "FAILED"}`);
    } catch {
      console.log("  npx test - SKIPPED");
    }
  } catch (err) {
    console.error(`\nTest failed: ${err}`);
  } finally {
    if (KEEP_RUNNING) {
      console.log(`\nVerdaccio is still running at ${REGISTRY}`);
      console.log("Try these commands to test manually:\n");
      console.log(`  npx --registry ${REGISTRY} ziex@${VERSION} version`);
      console.log(`  BUN_CONFIG_REGISTRY=${REGISTRY} bunx ziex@${VERSION} version`);
      console.log("\nPress Ctrl+C to stop verdaccio and clean up.");
      await new Promise<void>((resolve) => {
        process.on("SIGINT", () => {
          console.log("\nReceived SIGINT, cleaning up...");
          resolve();
        });
      });
    }
    // Cleanup
    console.log("\n5. Cleaning up...");
    verdaccioProc.kill();
    await $`rm -f ${join(platformPkgDir, ".npmrc")} ${join(mainPkgDir, ".npmrc")}`.quiet().nothrow();
    try {
      await $`npm uninstall -g ziex`.quiet().nothrow();
    } catch {}
    await $`rm -rf ${testDir}`.quiet().nothrow();
    console.log("Done!");
  }
}

main();
