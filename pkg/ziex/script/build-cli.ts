import { $ } from "bun";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";

/**
 * Build CLI platform packages for npm distribution.
 *
 * Usage:
 *   bun run script/build-cli.ts [--binary-dir <path>] [--version <version>]
 *
 * The binary-dir should contain release binaries named like:
 *   zx-macos-aarch64, zx-macos-x64, zx-linux-x64, zx-linux-aarch64,
 *   zx-windows-x64.exe, zx-windows-aarch64.exe
 *
 * If --binary-dir is not provided, it will look for the current platform
 * binary in zig-out/bin/release/.
 */

const PLATFORMS = [
  { npm: "@ziex/cli-darwin-arm64", target: "macos-aarch64", os: "darwin", cpu: "arm64", ext: "" },
  { npm: "@ziex/cli-darwin-x64", target: "macos-x64", os: "darwin", cpu: "x64", ext: "" },
  { npm: "@ziex/cli-linux-x64", target: "linux-x64", os: "linux", cpu: "x64", ext: "" },
  { npm: "@ziex/cli-linux-arm64", target: "linux-aarch64", os: "linux", cpu: "arm64", ext: "" },
  { npm: "@ziex/cli-win32-x64", target: "windows-x64", os: "win32", cpu: "x64", ext: ".exe" },
  { npm: "@ziex/cli-win32-arm64", target: "windows-aarch64", os: "win32", cpu: "arm64", ext: ".exe" },
] as const;

function parseArgs() {
  const args = process.argv.slice(2);
  let binaryDir = "";
  let version = "";
  let registry = "";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--binary-dir" && args[i + 1]) {
      binaryDir = args[++i];
    } else if (args[i] === "--version" && args[i + 1]) {
      version = args[++i];
    } else if (args[i] === "--registry" && args[i + 1]) {
      registry = args[++i];
    }
  }
  return { binaryDir, version, registry };
}

async function main() {
  const rootDir = join(import.meta.dir, "..");
  const distDir = join(rootDir, "dist-cli");
  const { binaryDir, version: versionArg, registry } = parseArgs();

  // Read version from package.json
  const pkgJson = JSON.parse(readFileSync(join(rootDir, "package.json"), "utf-8"));
  const version = versionArg || pkgJson.version;

  console.log(`Building CLI packages v${version}...`);

  // Clean dist
  await $`rm -rf ${distDir}`.quiet().nothrow();
  mkdirSync(distDir, { recursive: true });

  let builtCount = 0;

  for (const platform of PLATFORMS) {
    const binaryName = `zx-${platform.target}${platform.ext}`;
    const binaryPath = binaryDir
      ? join(binaryDir, binaryName)
      : join(rootDir, "../../zig-out/bin/release", binaryName);

    if (!existsSync(binaryPath)) {
      console.log(`  Skipping ${platform.npm} (binary not found: ${binaryName})`);
      continue;
    }

    console.log(`  Building ${platform.npm}...`);

    const pkgDir = join(distDir, platform.npm.replace("/", "-"));
    const binDir = join(pkgDir, "bin");
    mkdirSync(binDir, { recursive: true });

    // Copy binary
    const destBinaryName = `zx${platform.ext}`;
    copyFileSync(binaryPath, join(binDir, destBinaryName));

    // Read template package.json
    const templatePath = join(rootDir, "npm", platform.npm, "package.json");
    const templateJson = JSON.parse(readFileSync(templatePath, "utf-8"));

    // Update version and bin
    templateJson.version = version;
    templateJson.bin = {
      zx: `bin/${destBinaryName}`,
      ziex: `bin/${destBinaryName}`,
    };

    writeFileSync(join(pkgDir, "package.json"), JSON.stringify(templateJson, null, 2));
    builtCount++;
  }

  // Build main package dist with updated optionalDependencies versions
  console.log(`\n  Building main ziex package...`);
  const mainDistDir = join(distDir, "ziex");
  mkdirSync(join(mainDistDir, "bin"), { recursive: true });

  // Copy install.js
  copyFileSync(join(rootDir, "install.cjs"), join(mainDistDir, "install.cjs"));

  // Copy bin stub
  copyFileSync(join(rootDir, "bin/ziex"), join(mainDistDir, "bin/ziex"));

  // Update main package.json
  const mainPkgJson = { ...pkgJson };
  mainPkgJson.version = version;
  mainPkgJson.private = undefined;
  mainPkgJson.scripts = { postinstall: "node install.cjs" };
  mainPkgJson.devDependencies = undefined;
  mainPkgJson.peerDependencies = undefined;
  mainPkgJson.peerDependenciesMeta = undefined;
  mainPkgJson.release = undefined;

  // Update optionalDependencies versions
  if (mainPkgJson.optionalDependencies) {
    for (const key of Object.keys(mainPkgJson.optionalDependencies)) {
      mainPkgJson.optionalDependencies[key] = version;
    }
  }

  writeFileSync(join(mainDistDir, "package.json"), JSON.stringify(mainPkgJson, null, 2));

  console.log(`\nBuilt ${builtCount} platform packages + main package in ${distDir}`);

  // Publish if registry is provided
  if (registry) {
    console.log(`\nPublishing to ${registry}...`);
    for (const platform of PLATFORMS) {
      const pkgDir = join(distDir, platform.npm.replace("/", "-"));
      if (!existsSync(join(pkgDir, "package.json"))) continue;
      try {
        await $`cd ${pkgDir} && npm publish --registry ${registry}`.quiet();
        console.log(`  Published ${platform.npm}`);
      } catch (e) {
        console.log(`  Skipped ${platform.npm} (already published or error)`);
      }
    }
    try {
      await $`cd ${mainDistDir} && npm publish --registry ${registry}`.quiet();
      console.log(`  Published ziex`);
    } catch (e) {
      console.log(`  Skipped ziex (already published or error)`);
    }
  }
}

main();
