# @ziex/cli

Ziex CLI distribution via NPM.

## Usage

```bash
# Run directly
npx @ziex/cli version
bunx @ziex/cli version

# Or install globally
npm install -g @ziex/cli
zig version
```

## How it works

The `@ziex/cli` package resolves the correct native binary for your platform via optional dependencies:

| Package | Platform |
|---------|----------|
| `@ziex/cli-darwin-arm64` | macOS Apple Silicon |
| `@ziex/cli-darwin-x64` | macOS Intel |
| `@ziex/cli-linux-x64` | Linux x64 |
| `@ziex/cli-linux-arm64` | Linux ARM64 |
| `@ziex/cli-win32-x64` | Windows x64 |
| `@ziex/cli-win32-arm64` | Windows ARM64 |