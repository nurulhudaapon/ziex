#!/bin/bash
set -euo pipefail

# Smoke-tests @ziex/cli and ziex packages by publishing to a local
# Verdaccio registry and verifying that the CLI binary works.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
VERDACCIO_DIR="$SCRIPT_DIR/@ziex"
REGISTRY="http://localhost:4873"
PASSED=0
FAILED=0
VERSION="${1:-}"

cleanup() {
  if [ -n "${VERDACCIO_PID:-}" ]; then
    kill "$VERDACCIO_PID" 2>/dev/null || true
    wait "$VERDACCIO_PID" 2>/dev/null || true
  fi
  rm -rf "$SCRIPT_DIR/_check_tmp" "$SCRIPT_DIR/_check_npmrc"
}
trap cleanup EXIT

# Resolve expected version
if [ -z "$VERSION" ]; then
  VERSION=$(sed -n 's/.*\.version *= *"\([^"]*\)".*/\1/p' "$ROOT_DIR/build.zig.zon")
fi
echo "==> Checking packages at version $VERSION"

# Use a clean .npmrc scoped to this script so CI's global auth config
# (written by setup-node) doesn't interfere with local Verdaccio.
export npm_config_userconfig="$SCRIPT_DIR/_check_npmrc"
cat > "$npm_config_userconfig" <<EOF
registry=$REGISTRY
//localhost:4873/:_authToken=local-dev-token
EOF

# Start Verdaccio only if not running in CI
if [ -z "${CI:-}" ]; then
  echo "==> Starting local registry..."
  rm -rf "$VERDACCIO_DIR/.verdaccio-storage"
  npx --yes verdaccio --config "$VERDACCIO_DIR/verdaccio.yaml" --listen 4873 &
  VERDACCIO_PID=$!

  # Wait for Verdaccio to be ready (up to 60s; npx may need time to install verdaccio)
  for i in $(seq 1 120); do
    if curl -sf "$REGISTRY/-/ping" > /dev/null 2>&1; then break; fi
    sleep 0.5
  done
else
  echo "==> Skipping Verdaccio startup in CI"
fi

# Publish @ziex/cli* packages to local registry
echo "==> Publishing @ziex/cli* to local registry..."
cd "$VERDACCIO_DIR"
npm publish --workspaces --access public --tag dev --registry "$REGISTRY" 2>&1

# Build and publish ziex to local registry
echo "==> Building and publishing ziex to local registry..."
cd "$SCRIPT_DIR/ziex"
npm_config_registry="$REGISTRY" bun install
bun run build
cd dist
npm publish --access public --tag dev --registry "$REGISTRY" 2>&1

# Create temp directory for testing
mkdir -p "$SCRIPT_DIR/_check_tmp"
cd "$SCRIPT_DIR/_check_tmp"

pass() { PASSED=$((PASSED + 1)); echo "  PASS: $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL: $1"; }

# --- Tests ---

echo ""
echo "Running checks..."

# Check @ziex/cli version command
echo ""
CLI_OUTPUT=$(npx --yes --registry "$REGISTRY" @ziex/cli@dev version 2>&1) || true
if echo "$CLI_OUTPUT" | grep -q "$VERSION"; then
  pass "npx @ziex/cli version > $VERSION"
else
  fail "npx @ziex/cli version expected '$VERSION', got: $CLI_OUTPUT"
fi

# Check ziex version command (delegates to @ziex/cli)
ZIEX_OUTPUT=$(npx --yes --registry "$REGISTRY" ziex@dev version 2>&1) || true
if echo "$ZIEX_OUTPUT" | grep -q "$VERSION"; then
  pass "npx ziex version > $VERSION"
else
  fail "npx ziex version expected '$VERSION', got: $ZIEX_OUTPUT"
fi

# Check that ziex resolves @ziex/cli as dependency
ZIEX_HELP=$(npx --yes --registry "$REGISTRY" ziex@dev --help 2>&1) || true
if [ -n "$ZIEX_HELP" ]; then
  pass "npx ziex --help produces output"
else
  fail "npx ziex --help produced no output"
fi

# Check bunx compatibility
if command -v bunx &> /dev/null; then
  echo ""
  BUNX_OUTPUT=$(timeout 60 env BUN_CONFIG_REGISTRY="$REGISTRY" BUN_CONFIG_IGNORE_SCRIPTS=true bunx --verbose @ziex/cli@dev version 2>&1) || true
  if echo "$BUNX_OUTPUT" | grep -q "$VERSION"; then
    pass "bunx @ziex/cli version > $VERSION"
  else
    fail "bunx @ziex/cli version expected '$VERSION', got: $BUNX_OUTPUT"
  fi
  BUNX_ZIEX_OUTPUT=$(timeout 60 env BUN_CONFIG_REGISTRY="$REGISTRY" BUN_CONFIG_IGNORE_SCRIPTS=true bunx --verbose ziex@dev version 2>&1) || true
  if echo "$BUNX_ZIEX_OUTPUT" | grep -q "$VERSION"; then
    pass "bunx ziex version > $VERSION"
  else
    fail "bunx ziex version expected '$VERSION', got: $BUNX_ZIEX_OUTPUT"
  fi
fi

# --- Summary ---
echo ""
echo "  Results: $PASSED passed, $FAILED failed"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
