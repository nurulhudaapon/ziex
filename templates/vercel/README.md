# Ziex App on Vercel

> A starter template for building web applications with [Ziex](https://ziex.dev) deployed on [Vercel](https://vercel.com/).

**[Documentation →](https://ziex.dev)**

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/ziex-dev/template-vercel)

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

**3. Install Node.js** (for Vercel CLI)

[_Download →_](https://nodejs.org/)

## Project Structure

```
├── api/
│   └── index.ts        # Vercel Edge Function entrypoint
│   └── nodejs.ts       # Vercel Node.js Function entrypoint
├── app/
│   ├── assets/         # Static assets (CSS, images, etc)
│   ├── main.zig        # Zig entrypoint
│   ├── pages/          # Pages (Zig/ZX)
│   │   ├── layout.zx   # Root layout
│   │   ├── page.zx     # Home page
│   │   ├── client.zx   # Client-side component
│   │   └── ...
│   └── public/         # Public static files (favicon, etc)
├── build.zig           # Zig build script
├── build.zig.zon       # Zig package manager config
└── package.json
```

## Usage

By default the app is configured to use Vercel Edge Functions. If you want to use Node.js runtime instead, update .vercelignore to remove `api/nodejs.ts` and update `vercel.json` to point to `api/nodejs.ts` as the entrypoint.

### Development

```bash
vercel dev
```

App will be available at [`http://localhost:3000`](http://localhost:3000) with hot reload enabled.

### Deploy to Vercel

```bash
vercel deploy
```

Or click the **Deploy with Vercel** button above for one-click deployment.

## Contributing

Contributions are welcome! For feature requests, bug reports, or questions, see the [Ziex Repo](https://github.com/ziex-dev/ziex).

## Links

- [Documentation](https://ziex.dev)
- [Discord](https://ziex.dev/r/discord)
- [Vercel Docs](https://vercel.com/docs)
- [Zig Language](https://ziglang.org/)
