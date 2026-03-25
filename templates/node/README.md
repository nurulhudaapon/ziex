# Ziex App with Node Package Managers

>This is a starter template for building web applications with [Ziex](https://ziex.dev), a full-stack web framework for Zig.

This project can be used without having to installe Zig or Ziex globally, it works with any Node package manager (npm, yarn, pnpm, bun, etc).

**[Documentation →](https://ziex.dev)**


## Install Dependencies

You can use `bun`/`npm`/`yarn`/`pnpm` or any other Node package manager, the following guides uses Bun as an example.


```bash
bun install
```

## Usage

### Development
```bash
bun dev
```
App will be available at [`http://localhost:3000`](http://localhost:3000). with hot reload enabled.

### Serve Production Build
```bash
bun serve
```

### Exporting as Static Site
```bash
bun export
```
This will create a `dist/` directory with the static export of your app. You can deploy the contents of `dist/` to any static hosting provider (Netlify, Vercel, GitHub Pages, etc) or serve it with any static file server.

### Deployment

```bash
bun bundle
```

This will create a `bundle/` directory with the binary and static assets needed to run your app. You can deploy the contents of `bundle/` to any VPS.


### [ZX CLI](https://ziex.dev/reference#cli) Commands
```bash
bun zx [command] [options]
```

All ZX CLI commands are available under `bun zx [command]`. For example, to run auto formatter:
```bash
bun zx fmt .
```

## Contributing

Contributions are welcome! Feel free to open issues or pull requests. For feature requests, bug reports, or questions, see the [Ziex Repo](https://github.com/ziex-dev/ziex).

## Links

- [Documentation](https://ziex.dev)
- [Discord](https://ziex.dev/r/discord)
- [Topic on Ziggit](https://ziex.dev/r/ziggit)
- [Project on Zig Discord Community](https://ziex.dev/r/zig-discord) (Join Zig Discord first: https://discord.gg/zig)
- [GitHub](https://github.com/nurulhudaapon/ziex)
- [Zig Language](https://ziglang.org/)