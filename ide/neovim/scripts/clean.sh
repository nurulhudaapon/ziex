#!/bin/bash
# Test script: Clean everything and test fresh install

set -e

echo "🧹 Cleaning all ZX Neovim files..."

# Remove parser
echo "  ✓ Removing parser..."
rm -f ~/.local/share/nvim/site/parser/zx.so

# Remove queries (if symlinked)
echo "  ✓ Removing query symlinks..."
rm -rf ~/.local/share/nvim/site/queries/zx

# Clear caches
echo "  ✓ Clearing caches..."
rm -rf ~/.local/state/nvim/parser-cache
rm -rf ~/.cache/nvim/luac
rm -rf ~/.local/state/nvim/lazy

# Clear lazy.nvim plugin cache
echo "  ✓ Clearing lazy.nvim cache..."
rm -rf ~/.local/share/nvim/lazy/zx

echo ""
echo "✅ Everything cleaned!"
echo ""
echo "📝 Next steps:"
echo "  1. Restart Neovim: nvim"
echo "  2. Reload plugin: :Lazy reload zx"
echo "  3. Open test file: :e /tmp/test.zx"
echo ""
echo "Expected behavior:"
echo "  • Parser builds automatically"
echo "  • Syntax highlighting works"
echo "  • <leader>zt shows tree"
echo "  • <leader>zh shows highlights"

