#!/bin/bash
set -euo pipefail

# Downloads Zig compiler binaries for all platforms.
# Reads version from package.json.
# Places lib/ in the shared @zigc/lib package (identical across platforms).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIEX_VER=$(node -p "require('$SCRIPT_DIR/package.json').version")
LIB_COPIED=false

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

# Copy README.md to all packages
echo "Copying README.md to all packages..."
for dir in cli cli-darwin-arm64 cli-darwin-x64 cli-linux-x64 cli-linux-arm64 cli-win32-x64 cli-win32-arm64; do
  cp "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/$dir/README.md"
done

echo "All packages ready!"
