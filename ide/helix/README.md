
# Helix

## 1. Language & Grammar Setup

Add the following entries to your Helix `~/.config/helix/languages.toml`:

```toml
[[language]]
name = "ziex"
language-id = "zx"
scope = "source.zx"
roots = ["build.zig", "zls.json", ".git"]
file-types = ["zx"]
grammar = "zx"
language-servers = ["zls-zx"]

[language-server.zls-zx]
command = "zls-zx-proxy"
args = ["zls"]

[[grammar]]
name = "zx"
source = { git = "https://github.com/nurulhudaapon/ziex", rev = "main", subpath = "pkg/tree-sitter-zx" }
```

---

## 2. Build Grammar

Fetch and build the grammar:

```sh
hx --grammar fetch
hx --grammar build
```

---

## 3. Copy Queries

Clone this repo, then copy the queries for zx:

```sh
cp -r ide/helix/queries/ziex/ ~/.config/helix/runtime/queries/ziex/
```

---

## 4. Configure LSP Proxy

The zx language server (`zls`) reports `expected expression, found '<'` for zx tags. The proxy silences this error and allows LSP features to work correctly.

Copy the proxy script:

```sh
cp ide/helix/scripts/zls-zx-proxy ~/.local/bin/zls-zx-proxy
```
