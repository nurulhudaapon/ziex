# Benchmarks

## SSR Throughput

### Next.js

From the `bench/nextjs` directory, run:

```sh
npm install
npm run build
npm run start
```

Then run the benchmark:

```sh
oha -n 10000 -c 100 http://localhost:3000/ssr
```

### Ziex

From the `bench/ziex` directory, run:

```sh
zig build -Doptimize=ReleaseFast
./zig-out/bin/ziex
```

Then run the benchmark:

```sh
oha -n 10000 -c 100 http://localhost:3000/ssr
```

### Leptos

From the `bench/leptos` directory, run:

```sh
cargo leptos serve --release
```

Then run the benchmark:

```sh
oha -n 10000 -c 100 http://localhost:3000/ssr
```