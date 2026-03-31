#!/bin/bash
set -euo pipefail

# Prepares @ziex npm packages for publishing.
# Reads version from the root build.zig.zon.
# Copies platform binaries and syncs package versions.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/../.."

# Use version argument if provided, otherwise read from build.zig.zon
if [[ "${1:-}" != "" && "${1:-}" != "--version" ]]; then
  ZIEX_VER="$1"
  shift
else
  ZIEX_VER=$(sed -n 's/.*\.version *= *"\([^"]*\)".*/\1/p' "$ROOT_DIR/build.zig.zon")
fi

# Update version in all workspace package.json files
echo "Updating package versions to $ZIEX_VER..."
for pkg in cli cli-darwin-arm64 cli-darwin-x64 cli-linux-x64 cli-linux-arm64 cli-win32-x64 cli-win32-arm64; do
  pkg_json="$SCRIPT_DIR/$pkg/package.json"
  [ -f "$pkg_json" ] || continue
  node -e "
    const fs = require('fs'), path = require('path');
    const pkgJson = path.resolve(process.argv[1]);
    const ver = process.argv[2];
    const p = JSON.parse(fs.readFileSync(pkgJson, 'utf8'));
    p.version = ver;
    for (const key of ['dependencies', 'optionalDependencies']) {
      if (!p[key]) continue;
      for (const dep of Object.keys(p[key])) {
        if (dep.startsWith('@ziex/cli-')) p[key][dep] = ver;
      }
    }
    fs.writeFileSync(pkgJson, JSON.stringify(p, null, 2) + '\n');
  " "$pkg_json" "$ZIEX_VER"
done

# Also sync version in pkg/ziex (the main framework package)
ZIEX_PKG_JSON="$ROOT_DIR/pkg/ziex/package.json"
if [ -f "$ZIEX_PKG_JSON" ]; then
  echo "Updating ziex package version to $ZIEX_VER..."
  node -e "
    const fs = require('fs'), path = require('path');
    const pkgJson = path.resolve(process.argv[1]);
    const ver = process.argv[2];
    const p = JSON.parse(fs.readFileSync(pkgJson, 'utf8'));
    p.version = ver;
    if (p.dependencies?.['@ziex/cli']) p.dependencies['@ziex/cli'] = ver;
    for (const key of ['optionalDependencies']) {
      if (!p[key]) continue;
      for (const dep of Object.keys(p[key])) {
        if (dep.startsWith('@ziex/cli')) p[key][dep] = ver;
      }
    }
    fs.writeFileSync(pkgJson, JSON.stringify(p, null, 2) + '\n');
  " "$ZIEX_PKG_JSON" "$ZIEX_VER"
fi

# --version: only sync package versions, skip downloads
if [[ "${1:-}" == "--version" ]]; then
  echo "Done."
  exit 0
fi

# Copy binaries from zig-out/bin/release to respective platform packages
RELEASE_DIR="$SCRIPT_DIR/../../zig-out/bin/release"

PKGS="cli-darwin-arm64 cli-darwin-x64 cli-linux-x64 cli-linux-arm64 cli-win32-x64 cli-win32-arm64"
BINS="zx-macos-aarch64 zx-macos-x64 zx-linux-x64 zx-linux-aarch64 zx-windows-x64.exe zx-windows-aarch64.exe"

echo "Copying binaries from $RELEASE_DIR..."
set -- $BINS
for pkg in $PKGS; do
  bin="$1"; shift
  src="$RELEASE_DIR/$bin"
  dest_dir="$SCRIPT_DIR/$pkg/bin"
  if [[ "$pkg" == cli-win32-* ]]; then
    dest="$dest_dir/zx.exe"
  else
    dest="$dest_dir/zx"
  fi

  if [ -f "$src" ]; then
    mkdir -p "$dest_dir"
    cp "$src" "$dest"
    chmod +x "$dest"
    echo "  Copied $bin -> $pkg/bin/"
  else
    echo "  Warning: $src not found, skipping $pkg"
  fi
done

# Copy README.md to all packages
echo "Copying README.md to all packages..."
for dir in cli cli-darwin-arm64 cli-darwin-x64 cli-linux-x64 cli-linux-arm64 cli-win32-x64 cli-win32-arm64; do
  cp "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/$dir/README.md"
done

echo "All packages ready!"
