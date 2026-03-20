# Ziex App on Cloudflare

> A starter template for building web applications with [Ziex](https://ziex.dev) deployed on [Cloudflare Workers](https://workers.cloudflare.com/).

**[Documentation →](https://ziex.dev)**

[![Deploy to Cloudflare Workers](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/ziex-dev/template-cloudflare)

## Getting Started

### Prerequisites

**1. Install ZX CLI**

```bash
# Linux/macOS
curl -fsSL https://ziex.dev/install | bash

# Windows
powershell -c "irm ziex.dev/install.ps1 | iex"
```

**2. Install Zig**

```bash
brew install zig  # macOS
winget install -e --id zig.zig  # Windows
```

[_Other platforms →_](https://ziglang.org/learn/getting-started/)

**3. Install Node.js** (for Wrangler)

[_Download →_](https://nodejs.org/)

## Project Structure

```
├── app/
│   ├── assets/         # Static assets (CSS, images, etc)
│   ├── main.ts         # Cloudflare Worker entrypoint
│   ├── main.zig        # Zig entrypoint
│   ├── pages/          # Pages (Zig/ZX)
│   │   ├── layout.zx   # Root layout
│   │   ├── page.zx     # Home page
│   │   ├── client.zx   # Client-side component
│   │   └── ...
│   └── public/         # Public static files (favicon, etc)
├── build.zig           # Zig build script
├── build.zig.zon       # Zig package manager config
├── wrangler.jsonc      # Cloudflare Workers config
└── package.json
```

## Usage

### Development

```bash
zig build dev
```

App will be available at [`http://localhost:3000`](http://localhost:3000) with hot reload enabled.

### Deploy to Cloudflare

```bash
npx wrangler deploy
```

Or click the **Deploy to Cloudflare Workers** button above for one-click deployment.

## Contributing

Contributions are welcome! For feature requests, bug reports, or questions, see the [Ziex Repo](https://github.com/ziex-dev/ziex).

## Links

- [Documentation](https://ziex.dev)
- [Discord](https://ziex.dev/r/discord)
- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [Zig Language](https://ziglang.org/)
