# Helix Support for zx

## Installation

1) Add the language and grammar entries to your Helix `languages.toml`:

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

2) Build the grammar:

```sh
hx --grammar fetch
hx --grammar build
```

3) Copy the queries in `ide/helix/queries/ziex` into:

```
~/.config/helix/runtime/queries/ziex
```
4) Configure LSP:

`zls` reports `expected expression, found '<'` for zx tags. Helix cannot filter
diagnostics, so this repo includes a small proxy that drops that error.

Copy:

```
ide/helix/scripts/zls-zx-proxy
```

to:

```
~/.local/bin/zls-zx-proxy
```
