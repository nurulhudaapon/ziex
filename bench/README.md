# Benchmark

Compares SSR performance of web frameworks inside Docker containers.

## Prerequisites

- Docker

## Usage

Clone the repository and run the benchmark script:

```bash
cd bench

# all frameworks
bash run.sh

# specific framework (e.g., Ziex)
bash run.sh ziex
```

Results are written to `result.csv`.