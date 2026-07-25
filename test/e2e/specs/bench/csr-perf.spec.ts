import { test, expect, type Page } from '@playwright/test';

/**
 * Stable CSR DOM timings (median of a few in-page samples).
 *
 *   cd bench/ziex && zig build serve
 *   CSR_BENCH=1 BASE_URL=http://localhost:3000 \
 *     npx playwright test specs/bench/csr-perf.spec.ts --workers=1 --retries=0
 *
 * Env:
 *   CSR_BENCH_ITERS   measured samples (default 3)
 *   CSR_BENCH_WARMUP  discarded warmups (default 1)
 *   CSR_BENCH_FULL=1  also run per-op 10k tests (slower)
 */
if (process.env.CSR_BENCH) {
  const ITERS = Math.max(1, Number(process.env.CSR_BENCH_ITERS ?? 3));
  const WARMUP = Math.max(0, Number(process.env.CSR_BENCH_WARMUP ?? 1));
  const FULL = !!process.env.CSR_BENCH_FULL;

  test.use({ video: 'off', screenshot: 'off', trace: 'off' });

  test.describe('CSR performance (stable)', () => {
    test.describe.configure({ mode: 'serial', retries: 0, timeout: 300_000 });

    test.beforeEach(async ({ page }) => {
      await page.goto('/js-framework-benchmark/csr', { waitUntil: 'domcontentloaded' });
      await expect(page.getByRole('heading', { name: /Ziex Client-Side keyed/i })).toBeVisible({
        timeout: 30_000,
      });
      await settle(page);
    });

    test('stress: 10k → update → append → swap → clear', async ({ page }) => {
      const samples: PipelineSample[] = [];

      for (let i = 0; i < WARMUP + ITERS; i++) {
        await clickUntil(page, '#clear', () => inPageRowCount(page, 0));
        await settle(page);

        const create = await timedInPage(page, '#runlots', { rows: 10_000 }, 60_000);
        const update = await timedInPage(page, '#update', { labelIncludes: '!!!' }, 60_000);
        const append = await timedInPage(page, '#add', { rows: 11_000 }, 60_000);
        const swap = await timedInPage(page, '#swaprows', { swapRowIdChanged: true }, 60_000);
        const clear = await timedInPage(page, '#clear', { rows: 0 }, 60_000);
        const total = create + update + append + swap + clear;

        if (i < WARMUP) continue;
        samples.push({ create, update, append, swap, clear, total });
      }

      console.log(`--- stress pipeline (${ITERS} samples, ${WARMUP} warmup) ---`);
      logStats('  create 10k', summarize(samples.map((s) => s.create)));
      logStats('  update 10k', summarize(samples.map((s) => s.update)));
      logStats('  append 1k', summarize(samples.map((s) => s.append)));
      logStats('  swap', summarize(samples.map((s) => s.swap)));
      logStats('  clear', summarize(samples.map((s) => s.clear)));
      const totalStats = summarize(samples.map((s) => s.total));
      logStats('csr stress pipeline', totalStats);
      expect(totalStats.median).toBeLessThan(12_000);
    });

    if (FULL) {
      test('create 10,000 rows', async ({ page }) => {
        const stats = await measureOp(page, {
          warmup: WARMUP,
          iters: ITERS,
          prepare: async () => {
            await clickUntil(page, '#clear', () => inPageRowCount(page, 0));
            await settle(page);
          },
          run: () => timedInPage(page, '#runlots', { rows: 10_000 }, 60_000),
        });
        logStats('csr create 10k', stats);
        expect(stats.median).toBeLessThan(5_000);
      });

      test('update every 10th row (10k)', async ({ page }) => {
        const stats = await measureOp(page, {
          warmup: WARMUP,
          iters: ITERS,
          prepare: async () => {
            await clickUntil(page, '#clear', () => inPageRowCount(page, 0));
            await clickUntil(page, '#runlots', () => inPageRowCount(page, 10_000), 60_000);
            await settle(page);
          },
          run: () => timedInPage(page, '#update', { labelIncludes: '!!!' }, 60_000),
        });
        logStats('csr update 10k', stats);
        expect(stats.median).toBeLessThan(2_000);
      });

      test('append 1,000 onto 10,000', async ({ page }) => {
        const stats = await measureOp(page, {
          warmup: WARMUP,
          iters: ITERS,
          prepare: async () => {
            await clickUntil(page, '#clear', () => inPageRowCount(page, 0));
            await clickUntil(page, '#runlots', () => inPageRowCount(page, 10_000), 60_000);
            await settle(page);
          },
          run: () => timedInPage(page, '#add', { rows: 11_000 }, 60_000),
        });
        logStats('csr append 1k→10k', stats);
        expect(stats.median).toBeLessThan(1_000);
      });

      test('swap rows (10k)', async ({ page }) => {
        const stats = await measureOp(page, {
          warmup: WARMUP,
          iters: ITERS,
          prepare: async () => {
            await clickUntil(page, '#clear', () => inPageRowCount(page, 0));
            await clickUntil(page, '#runlots', () => inPageRowCount(page, 10_000), 60_000);
            await settle(page);
          },
          run: () => timedInPage(page, '#swaprows', { swapRowIdChanged: true }, 60_000),
        });
        logStats('csr swap 10k', stats);
        expect(stats.median).toBeLessThan(2_000);
      });

      test('clear rows (10k)', async ({ page }) => {
        const stats = await measureOp(page, {
          warmup: WARMUP,
          iters: ITERS,
          prepare: async () => {
            await clickUntil(page, '#runlots', () => inPageRowCount(page, 10_000), 60_000);
            await settle(page);
          },
          run: () => timedInPage(page, '#clear', { rows: 0 }, 60_000),
        });
        logStats('csr clear 10k', stats);
        expect(stats.median).toBeLessThan(2_000);
      });
    }
  });
}

type ReadySpec = {
  rows?: number;
  labelIncludes?: string;
  swapRowIdChanged?: boolean;
};

type Stats = { median: number; min: number; max: number; mean: number; samples: number[] };
type PipelineSample = {
  create: number;
  update: number;
  append: number;
  swap: number;
  clear: number;
  total: number;
};

async function measureOp(
  page: Page,
  opts: {
    warmup: number;
    iters: number;
    prepare: () => Promise<void>;
    run: () => Promise<number>;
  },
): Promise<Stats> {
  const samples: number[] = [];
  for (let i = 0; i < opts.warmup + opts.iters; i++) {
    await opts.prepare();
    const ms = await opts.run();
    if (i >= opts.warmup) samples.push(ms);
  }
  return summarize(samples);
}

/** Time a click entirely in-page (no Playwright poll round-trips in the timer). */
async function timedInPage(page: Page, selector: string, ready: ReadySpec, timeoutMs = 30_000): Promise<number> {
  return page.evaluate(
    async ({ selector: sel, ready: spec, timeoutMs: limit }) => {
      const btn = document.querySelector(sel);
      if (!(btn instanceof HTMLElement)) throw new Error(`missing ${sel}`);

      const tbody = document.querySelector('tbody');
      if (!tbody) throw new Error('missing tbody');

      const rowId = (): string | null => {
        const cell = tbody.querySelector('tr:nth-child(2) > td.col-md-1');
        return cell?.textContent ?? null;
      };
      const firstLabel = (): string =>
        tbody.querySelector('tr td.col-md-4 a')?.textContent ?? '';

      const beforeId = spec.swapRowIdChanged ? rowId() : null;
      const done = (): boolean => {
        if (spec.rows !== undefined) return tbody.querySelectorAll('tr').length === spec.rows;
        if (spec.labelIncludes !== undefined) return firstLabel().includes(spec.labelIncludes);
        if (spec.swapRowIdChanged) return rowId() !== beforeId;
        return false;
      };

      await new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r())));

      const start = performance.now();
      btn.click();

      await new Promise<void>((resolve, reject) => {
        if (done()) {
          resolve();
          return;
        }
        const timer = window.setTimeout(() => {
          obs.disconnect();
          reject(new Error(`timeout waiting after ${sel}`));
        }, limit);
        const obs = new MutationObserver(() => {
          if (!done()) return;
          window.clearTimeout(timer);
          obs.disconnect();
          resolve();
        });
        obs.observe(tbody, { childList: true, subtree: true, characterData: true, attributes: true });
      });

      await new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r())));
      return performance.now() - start;
    },
    { selector, ready, timeoutMs },
  );
}

async function clickUntil(
  page: Page,
  selector: string,
  ready: () => Promise<boolean>,
  timeout = 30_000,
): Promise<void> {
  if (await ready()) return;
  await page.locator(selector).click();
  await expect.poll(ready, { timeout }).toBeTruthy();
}

async function inPageRowCount(page: Page, n: number): Promise<boolean> {
  return page.evaluate((want) => document.querySelectorAll('tbody tr').length === want, n);
}

async function settle(page: Page): Promise<void> {
  await page.evaluate(
    () =>
      new Promise<void>((r) => {
        requestAnimationFrame(() => requestAnimationFrame(() => r()));
      }),
  );
}

function summarize(samples: number[]): Stats {
  const sorted = [...samples].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  const median =
    sorted.length % 2 === 0 ? (sorted[mid - 1]! + sorted[mid]!) / 2 : sorted[mid]!;
  const sum = samples.reduce((a, b) => a + b, 0);
  return {
    median,
    min: sorted[0]!,
    max: sorted[sorted.length - 1]!,
    mean: sum / samples.length,
    samples,
  };
}

function logStats(label: string, stats: Stats): void {
  const fmt = (n: number) => n.toFixed(1);
  const list = stats.samples.map(fmt).join(', ');
  console.log(
    `${label}: median=${fmt(stats.median)}ms min=${fmt(stats.min)} max=${fmt(stats.max)} mean=${fmt(stats.mean)}  [${list}]`,
  );
}
