#!/bin/bash
set -euo pipefail

# Downloads Zig compiler binaries for all platforms.
# Reads version from package.json.
# Places lib/ in the shared @zigc/lib package (identical across platforms).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_VER=$(node -p "require('$SCRIPT_DIR/package.json').version")
LIB_DIR="$SCRIPT_DIR/lib"
CACHE_DIR="$SCRIPT_DIR/.cache"
LIB_COPIED=false

# Zig signing public key (from https://ziglang.org/download/)
ZIG_PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

# For dev versions, read full version (with +hash) from index.json
# npm strips the +hash from package.json versions
ZIG_FULL_VER="$ZIG_VER"
if [[ "$ZIG_VER" == *"-dev"* ]] && [ -f "$SCRIPT_DIR/index.json" ]; then
  ZIG_FULL_VER=$(node -p "require('$SCRIPT_DIR/index.json').master.version")
fi

# Update version in all workspace package.json files
echo "Updating package versions to $ZIG_VER..."
for pkg in lib cli darwin-arm64 darwin-x64 linux-x64 linux-arm64 win32-x64 win32-arm64; do
  pkg_json="$SCRIPT_DIR/$pkg/package.json"
  [ -f "$pkg_json" ] || continue
  node -e "
    const fs = require('fs');
    const p = JSON.parse(fs.readFileSync('$pkg_json', 'utf8'));
    p.version = '$ZIG_VER';
    // Update any @zigc/* refs in dependencies / optionalDependencies
    for (const key of ['dependencies', 'optionalDependencies']) {
      if (!p[key]) continue;
      for (const dep of Object.keys(p[key])) {
        if (dep.startsWith('@zigc/')) p[key][dep] = '$ZIG_VER';
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

# Dev builds use /builds/, releases use /download/<ver>/
if [[ "$ZIG_FULL_VER" == *"-dev"* ]]; then
  OFFICIAL_BASE="https://ziglang.org/builds"
else
  OFFICIAL_BASE="https://ziglang.org/download/${ZIG_FULL_VER}"
fi

# Check for minisign; prompt to continue without verification if missing
MINISIGN_AVAILABLE=true
if ! command -v minisign &>/dev/null; then
  MINISIGN_AVAILABLE=false
  echo "warning: 'minisign' not found — archive signatures cannot be verified."
  echo "  Install: https://jedisct1.github.io/minisign/"
  read -r -p "  Continue without signature verification? [y/N] " reply
  if [[ ! "$reply" =~ ^[yY]$ ]]; then
    exit 1
  fi
fi

# Fetch community mirrors, shuffle them, append official as final fallback
echo "Fetching mirrors..."
MIRROR_RAW=$(curl -fsSL "https://ziglang.org/download/community-mirrors.txt" 2>/dev/null || echo "")
SHUFFLED_MIRRORS=$(printf '%s\n' "$MIRROR_RAW" | python3 -c "
import sys, random
lines = [l.strip() for l in sys.stdin if l.strip()]
random.shuffle(lines)
print('\n'.join(lines))
")
# Append official base as last-resort fallback
SHUFFLED_MIRRORS="${SHUFFLED_MIRRORS}
${OFFICIAL_BASE}"

# --version: only sync package versions, skip downloads
if [[ "${1:-}" == "--version" ]]; then
  echo "Done."
  exit 0
fi

echo "Downloading Zig $ZIG_FULL_VER for all platforms..."

# Track version to detect stale binaries
VERSION_FILE="$SCRIPT_DIR/.zig-version"
OLD_VER=""
if [ -f "$VERSION_FILE" ]; then
  OLD_VER=$(cat "$VERSION_FILE")
fi

# If version changed, clean all binaries and lib
if [ -n "$OLD_VER" ] && [ "$OLD_VER" != "$ZIG_FULL_VER" ]; then
  echo "  Version changed ($OLD_VER -> $ZIG_VER), cleaning old binaries..."
  rm -rf "$SCRIPT_DIR"/darwin-arm64/bin "$SCRIPT_DIR"/darwin-x64/bin \
         "$SCRIPT_DIR"/linux-x64/bin "$SCRIPT_DIR"/linux-arm64/bin \
         "$SCRIPT_DIR"/win32-x64/bin "$SCRIPT_DIR"/win32-arm64/bin
  # Remove lib contents but preserve package.json
  find "$LIB_DIR" -mindepth 1 -not -name 'package.json' -delete 2>/dev/null || true
fi

# platform-dir  zig-target           archive-ext
PLATFORMS=(
  "darwin-arm64   aarch64-macos       tar.xz"
  "darwin-x64     x86_64-macos        tar.xz"
  "linux-x64      x86_64-linux        tar.xz"
  "linux-arm64    aarch64-linux       tar.xz"
  "win32-x64      x86_64-windows      zip"
  "win32-arm64    aarch64-windows     zip"
)

# Check if lib is already populated with actual Zig content
if [ -d "$LIB_DIR/std" ]; then
  LIB_COPIED=true
fi

for entry in "${PLATFORMS[@]}"; do
  read -r dir target ext <<< "$entry"
  pkg_dir="$SCRIPT_DIR/$dir"
  bin_dir="$pkg_dir/bin"
  mkdir -p "$bin_dir"

  if [ -f "$bin_dir/zig" ] || [ -f "$bin_dir/zig.exe" ]; then
    echo "  $dir: already exists, skipping"
    continue
  fi

  archive_name="zig-${target}-${ZIG_FULL_VER}.${ext}"
  extracted_dir="zig-${target}-${ZIG_FULL_VER}"
  cached_archive="$CACHE_DIR/$ZIG_FULL_VER/$archive_name"
  cached_minisig="${cached_archive}.minisig"

  # Try to use verified cached archive, otherwise fetch from mirrors
  _cache_valid() {
    [ -f "$cached_archive" ] || return 1
    if [ "$MINISIGN_AVAILABLE" = true ]; then
      [ -f "$cached_minisig" ] && \
        minisign -V -P "$ZIG_PUBKEY" -m "$cached_archive" -x "$cached_minisig" -q 2>/dev/null
    else
      return 0
    fi
  }

  if _cache_valid; then
    echo "  $dir: using cached archive"
  else
    rm -f "$cached_archive" "$cached_minisig"
    mkdir -p "$CACHE_DIR/$ZIG_FULL_VER"
    fetched=false

    while IFS= read -r mirror; do
      [ -z "$mirror" ] && continue
      url="${mirror}/${archive_name}"
      tmp_archive="${cached_archive}.tmp"
      tmp_minisig="${cached_minisig}.tmp"

      echo "  $dir: trying ${mirror}..."
      curl -fsSL "${url}?source=zigc-npm" -o "$tmp_archive" 2>/dev/null || { rm -f "$tmp_archive"; continue; }

      if [ "$MINISIGN_AVAILABLE" = true ]; then
        curl -fsSL "${url}.minisig?source=zigc-npm" -o "$tmp_minisig" 2>/dev/null || { rm -f "$tmp_archive" "$tmp_minisig"; continue; }

        # Verify signature
        if ! minisign -V -P "$ZIG_PUBKEY" -m "$tmp_archive" -x "$tmp_minisig" -q 2>/dev/null; then
          echo "  $dir: signature verification failed, skipping mirror"
          rm -f "$tmp_archive" "$tmp_minisig"
          continue
        fi

        # Verify filename in trusted comment to prevent downgrade attacks
        actual_name=$(grep "^trusted comment:" "$tmp_minisig" | sed 's/.*\bfile:\([^ \t]*\).*/\1/')
        if [ "$actual_name" != "$archive_name" ]; then
          echo "  $dir: filename mismatch in signature (got '$actual_name'), skipping mirror"
          rm -f "$tmp_archive" "$tmp_minisig"
          continue
        fi

        mv "$tmp_minisig" "$cached_minisig"
      fi

      mv "$tmp_archive" "$cached_archive"
      fetched=true
      break
    done <<< "$SHUFFLED_MIRRORS"

    if [ "$fetched" = false ]; then
      echo "  $dir: all mirrors failed"
      exit 1
    fi
  fi

  echo "  $dir: extracting..."
  if [ "$ext" = "zip" ]; then
    (cd "$pkg_dir" && unzip -qo "$cached_archive")
    cp "$pkg_dir/$extracted_dir/zig.exe" "$bin_dir/zig.exe"
  else
    (cd "$pkg_dir" && tar xf "$cached_archive")
    cp "$pkg_dir/$extracted_dir/zig" "$bin_dir/zig"
    chmod +x "$bin_dir/zig"
  fi

  # Copy lib/ to shared @zigc/lib package (only once, identical across platforms)
  if [ "$LIB_COPIED" = false ] && [ -d "$pkg_dir/$extracted_dir/lib" ]; then
    echo "  lib: copying shared lib/ from $dir"
    mkdir -p "$LIB_DIR"
    cp -r "$pkg_dir/$extracted_dir/lib/"* "$LIB_DIR/"
    LIB_COPIED=true
  fi

  # Clean up extracted directory (keep cached archive)
  rm -rf "$pkg_dir/$extracted_dir"
  echo "  $dir: done"
done

# If all binaries were already cached, lib may not have been copied yet — extract it now
if [ "$LIB_COPIED" = false ]; then
  for entry in "${PLATFORMS[@]}"; do
    read -r dir target ext <<< "$entry"
    archive_name="zig-${target}-${ZIG_FULL_VER}.${ext}"
    cached_archive="$CACHE_DIR/$ZIG_FULL_VER/$archive_name"
    extracted_dir="zig-${target}-${ZIG_FULL_VER}"
    pkg_dir="$SCRIPT_DIR/$dir"
    [ -f "$cached_archive" ] || continue

    echo "  lib: extracting from cached $dir archive..."
    if [ "$ext" = "zip" ]; then
      (cd "$pkg_dir" && unzip -qo "$cached_archive" "${extracted_dir}/lib/*")
    else
      (cd "$pkg_dir" && tar xf "$cached_archive" "${extracted_dir}/lib")
    fi
    mkdir -p "$LIB_DIR"
    cp -r "$pkg_dir/$extracted_dir/lib/"* "$LIB_DIR/"
    rm -rf "$pkg_dir/$extracted_dir"
    LIB_COPIED=true
    break
  done
fi

# Copy README.md to all packages
echo "Copying README.md to all packages..."
for dir in cli lib darwin-arm64 darwin-x64 linux-x64 linux-arm64 win32-x64 win32-arm64; do
  cp "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/$dir/README.md"
done

# Save current version
echo "$ZIG_FULL_VER" > "$VERSION_FILE"

echo "All platforms ready!"
