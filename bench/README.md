# Benchmark

Compares SSR performance of Ziex, Leptos, SolidStart, and Next.js in Docker containers limited to 2 CPUs and 2 GB RAM.

## Prerequisites

- Docker
- [oha](https://github.com/hatoo/oha) (`cargo install oha`)

## Usage

```bash
# all frameworks
./run.sh

# one or more
./run.sh ziex
./run.sh ziex leptos
```

Results are written to `result.csv` and `../site/pages/bench.zon` (used to generate the benchmark chart on ziex.dev).

## Measures:
- Requests per second (req/s)
- p50 latency
- p99 latency
- Idle memory (MB)
- Peak memory (MB)

## Frameworks

| Framework  | Port | Stack                    |
|------------|------|--------------------------|
| Ziex       | 3003 | Zig, native binary       |
| Leptos     | 3002 | Rust, Actix-web          |
| SolidStart | 3001 | Bun, Vinxi               |
| Next.js    | 3000 | Bun, React 19            |