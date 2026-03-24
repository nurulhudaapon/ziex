import { $ } from "bun";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";

/**
 * Publish all dist-cli packages to npm using workspaces.
 *
 * Usage:
 *   bun run script/publish-cli.ts [--tag <tag>] [--registry <url>] [--dry-run] [--otp <code>]
 *
 * Requires `bun run script/build-cli.ts` to have been run first.
 */

const DIST_CLI_DIR = join(import.meta.dir, "..", "dist-cli");

function parseArgs() {
  const args = process.argv.slice(2);
  let tag = "latest";
  let registry = "https://registry.npmjs.org";
  let dryRun = false;
  let otp = "";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--tag" && args[i + 1]) {
      tag = args[++i];
    } else if (args[i] === "--registry" && args[i + 1]) {
      registry = args[++i];
    } else if (args[i] === "--dry-run") {
      dryRun = true;
    } else if (args[i] === "--otp" && args[i + 1]) {
      otp = args[++i];
    }
  }
  return { tag, registry, dryRun, otp };
}

async function main() {
  if (!existsSync(DIST_CLI_DIR)) {
    console.error("dist-cli/ not found. Run `bun run script/build-cli.ts` first.");
    process.exit(1);
  }

  const { tag, registry, dryRun, otp } = parseArgs();

  // Discover all packages in dist-cli
  const entries = readdirSync(DIST_CLI_DIR, { withFileTypes: true });
  const packages = entries
    .filter((e) => e.isDirectory() && existsSync(join(DIST_CLI_DIR, e.name, "package.json")))
    .map((e) => {
      const pkgJson = JSON.parse(readFileSync(join(DIST_CLI_DIR, e.name, "package.json"), "utf-8"));
      return { dir: e.name, name: pkgJson.name, version: pkgJson.version };
    });

  if (packages.length === 0) {
    console.error("No packages found in dist-cli/.");
    process.exit(1);
  }

  // Generate a root package.json with workspaces
  const workspacePkgJson = {
    private: true,
    workspaces: packages.map((p) => p.dir),
  };
  writeFileSync(join(DIST_CLI_DIR, "package.json"), JSON.stringify(workspacePkgJson, null, 2));

  console.log(`Publishing ${packages.length} packages to ${registry} (tag: ${tag}):\n`);
  for (const pkg of packages) {
    console.log(`  ${pkg.name}@${pkg.version}`);
  }
  console.log();

  // Build npm publish args
  const publishArgs = ["npm", "publish", "--workspaces", "--tag", tag, "--registry", registry];
  if (dryRun) publishArgs.push("--dry-run");
  if (otp) publishArgs.push("--otp", otp);

  // Publish all at once via workspaces
  try {
    await $`cd ${DIST_CLI_DIR} && ${publishArgs}`;
    console.log(`\nAll packages published successfully!`);
  } catch (err) {
    console.error(`\nPublish failed: ${err}`);
    process.exit(1);
  } finally {
    // Clean up the generated workspace package.json
    await $`rm -f ${join(DIST_CLI_DIR, "package.json")}`.quiet().nothrow();
  }
}

main();
