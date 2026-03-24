// Postinstall script for ziex npm package
// Resolves the native binary from platform-specific optionalDependencies
// or falls back to downloading from GitHub releases.

const { existsSync, mkdirSync, copyFileSync, chmodSync, createWriteStream, unlinkSync } = require("fs");
const { execSync } = require("child_process");
const path = require("path");
const https = require("https");
const { createGunzip } = require("zlib");

const PLATFORM_MAP = {
  darwin: {
    arm64: { pkg: "@ziex/cli-darwin-arm64", target: "macos-aarch64" },
    x64: { pkg: "@ziex/cli-darwin-x64", target: "macos-x64" },
  },
  linux: {
    x64: { pkg: "@ziex/cli-linux-x64", target: "linux-x64" },
    arm64: { pkg: "@ziex/cli-linux-arm64", target: "linux-aarch64" },
  },
  win32: {
    x64: { pkg: "@ziex/cli-win32-x64", target: "windows-x64" },
    arm64: { pkg: "@ziex/cli-win32-arm64", target: "windows-aarch64" },
  },
};

const GITHUB_REPO = "ziex-dev/ziex";

function getPlatformInfo() {
  const os = process.platform;
  const arch = process.arch;
  const info = PLATFORM_MAP[os]?.[arch];
  if (!info) {
    throw new Error(`Unsupported platform: ${os}-${arch}`);
  }
  return info;
}

function getVersion() {
  const pkg = require("./package.json");
  return pkg.version;
}

function getBinaryName(target) {
  const isWindows = process.platform === "win32";
  return `zx-${target}${isWindows ? ".exe" : ""}`;
}

function getOutputPath() {
  const binDir = path.join(__dirname, "bin");
  const isWindows = process.platform === "win32";
  return path.join(binDir, isWindows ? "zx.exe" : "zx");
}

// Try to resolve binary from optionalDependencies
function tryResolveFromOptionalDep(pkgName) {
  try {
    const pkgPath = require.resolve(`${pkgName}/package.json`);
    const pkgDir = path.dirname(pkgPath);
    const pkgJson = require(pkgPath);
    const binName = pkgJson.bin?.zx || pkgJson.bin?.ziex;
    if (binName) {
      const binPath = path.join(pkgDir, binName);
      if (existsSync(binPath)) {
        return binPath;
      }
    }
    // Fallback: look for the binary directly
    const isWindows = process.platform === "win32";
    const possibleNames = isWindows ? ["zx.exe"] : ["zx"];
    for (const name of possibleNames) {
      const candidate = path.join(pkgDir, "bin", name);
      if (existsSync(candidate)) return candidate;
    }
  } catch {
    // Package not installed
  }
  return null;
}

// Download from GitHub releases
function downloadFromGitHub(target, version) {
  return new Promise((resolve, reject) => {
    const isWindows = process.platform === "win32";
    const ext = isWindows ? "zip" : "tar.gz";
    const tag = version.startsWith("0.") ? `zx-v${version}` : `zx-v${version}`;
    const url = `https://github.com/${GITHUB_REPO}/releases/download/${tag}/zx-${target}.${ext}`;
    const latestUrl = `https://github.com/${GITHUB_REPO}/releases/latest/download/zx-${target}.${ext}`;

    const binDir = path.join(__dirname, "bin");
    mkdirSync(binDir, { recursive: true });
    const archivePath = path.join(binDir, `zx-${target}.${ext}`);

    console.log(`Downloading ziex binary for ${target}...`);

    function download(downloadUrl, isRetry) {
      const followRedirect = (url) => {
        const proto = url.startsWith("https") ? https : require("http");
        proto
          .get(url, { headers: { "User-Agent": "ziex-npm" } }, (res) => {
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
              followRedirect(res.headers.location);
              return;
            }
            if (res.statusCode !== 200) {
              if (!isRetry) {
                // Retry with latest
                download(latestUrl, true);
                return;
              }
              reject(new Error(`Download failed with status ${res.statusCode}: ${downloadUrl}`));
              return;
            }

            const file = createWriteStream(archivePath);
            res.pipe(file);
            file.on("finish", () => {
              file.close(() => resolve(archivePath));
            });
          })
          .on("error", reject);
      };
      followRedirect(downloadUrl);
    }

    download(url, false);
  });
}

function extractTarGz(archivePath, targetBinaryName, outputPath) {
  const binDir = path.dirname(outputPath);
  // Use tar command (available on macOS and Linux)
  execSync(`tar -xzf "${archivePath}" -C "${binDir}"`, { stdio: "pipe" });
  const extractedPath = path.join(binDir, targetBinaryName);
  if (existsSync(extractedPath)) {
    copyFileSync(extractedPath, outputPath);
    unlinkSync(extractedPath);
  }
  unlinkSync(archivePath);
}

function extractZip(archivePath, targetBinaryName, outputPath) {
  const binDir = path.dirname(outputPath);
  execSync(`unzip -o "${archivePath}" -d "${binDir}"`, { stdio: "pipe" });
  const extractedPath = path.join(binDir, targetBinaryName);
  if (existsSync(extractedPath)) {
    copyFileSync(extractedPath, outputPath);
    unlinkSync(extractedPath);
  }
  unlinkSync(archivePath);
}

async function main() {
  const { pkg: pkgName, target } = getPlatformInfo();
  const outputPath = getOutputPath();
  const binDir = path.dirname(outputPath);
  mkdirSync(binDir, { recursive: true });

  // Step 1: Try to resolve from optional dependency
  const resolvedPath = tryResolveFromOptionalDep(pkgName);
  if (resolvedPath) {
    console.log(`Found ziex binary from ${pkgName}`);
    copyFileSync(resolvedPath, outputPath);
    chmodSync(outputPath, 0o755);

    // Create ziex alias (symlink or copy)
    createAliases(outputPath);
    return;
  }

  // Step 2: Download from GitHub releases
  console.log(`Platform package ${pkgName} not found, downloading from GitHub...`);
  try {
    const version = getVersion();
    const archivePath = await downloadFromGitHub(target, version);
    const binaryName = getBinaryName(target);
    const isWindows = process.platform === "win32";

    if (isWindows) {
      extractZip(archivePath, binaryName, outputPath);
    } else {
      extractTarGz(archivePath, binaryName, outputPath);
    }

    chmodSync(outputPath, 0o755);
    createAliases(outputPath);
    console.log("ziex binary installed successfully!");
  } catch (err) {
    console.error(`Failed to install ziex binary: ${err.message}`);
    console.error("You can install it manually from: https://ziex.dev/install");
    process.exit(1);
  }
}

function createAliases(zxPath) {
  const binDir = path.dirname(zxPath);
  const isWindows = process.platform === "win32";
  const ziexPath = path.join(binDir, isWindows ? "ziex.exe" : "ziex");

  // The main binary is `zx`, create `ziex` as a copy/symlink
  try {
    if (existsSync(ziexPath) && ziexPath !== zxPath) unlinkSync(ziexPath);
    if (ziexPath !== zxPath) {
      try {
        const fs = require("fs");
        fs.symlinkSync(path.basename(zxPath), ziexPath);
      } catch {
        copyFileSync(zxPath, ziexPath);
      }
    }
  } catch {
    // Non-critical
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
