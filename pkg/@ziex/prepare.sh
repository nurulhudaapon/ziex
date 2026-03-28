#!/bin/bash
set -euo pipefail

# Prepares @ziex npm packages for publishing.
# Reads version from the root build.zig.zon.
# Copies platform binaries and syncs package versions.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/../.."
ZIEX_VER=$(sed -n 's/.*\.version *= *"\([^"]*\)".*/\1/p' "$ROOT_DIR/build.zig.zon")

# Update version in all workspace package.json files
echo "Updating package versions to $ZIEX_VER..."
for pkg in cli cli-darwin-arm64 cli-darwin-x64 cli-linux-x64 cli-linux-arm64 cli-win32-x64 cli-win32-arm64; do
  pkg_json="$SCRIPT_DIR/$pkg/package.json"
  [ -f "$pkg_json" ] || continue
  node -e "
    const fs = require('fs');
    const p = JSON.parse(fs.readFileSync('$pkg_json', 'utf8'));
    p.version = '$ZIEX_VER';
    // Update any @ziex/cli-* refs in dependencies / optionalDependencies
    for (const key of ['dependencies', 'optionalDependencies']) {
      if (!p[key]) continue;
      for (const dep of Object.keys(p[key])) {
        if (dep.startsWith('@ziex/cli-')) p[key][dep] = '$ZIEX_VER';
      }
    }
    fs.writeFileSync('$pkg_json', JSON.stringify(p, null, 2) + '\n');
  "
done

# --version: only sync package versions, skip downloads
if [[ "${1:-}" == "--version" ]]; then
  echo "Done."
  exit 0
fi

# Copy binaries from zig-out/bin/release to respective platform packages
RELEASE_DIR="$SCRIPT_DIR/../../zig-out/bin/release"

declare -A BINARY_MAP=(
  ["cli-darwin-arm64"]="zx-macos-aarch64"
  ["cli-darwin-x64"]="zx-macos-x64"
  ["cli-linux-x64"]="zx-linux-x64"
  ["cli-linux-arm64"]="zx-linux-aarch64"
  ["cli-win32-x64"]="zx-windows-x64.exe"
  ["cli-win32-arm64"]="zx-windows-aarch64.exe"
)

echo "Copying binaries from $RELEASE_DIR..."
for pkg in "${!BINARY_MAP[@]}"; do
  src="$RELEASE_DIR/${BINARY_MAP[$pkg]}"
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
    echo "  Copied ${BINARY_MAP[$pkg]} -> $pkg/bin/"
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
