import { test, expect } from '@playwright/test';

/**
 * Full bridge+DOM CSR timings against the js-framework-benchmark page.
 * Requires the bench app (not `site`):
 *
 *   cd bench/ziex && zig build dev
 *   CSR_BENCH=1 BASE_URL=http://localhost:3000 npx playwright test specs/bench/csr-perf.spec.ts
 */
if (process.env.CSR_BENCH) {
  test.describe('CSR performance (js-framework-benchmark)', () => {
    test.beforeEach(async ({ page }) => {
      await page.goto('/js-framework-benchmark/csr');
      await expect(page.getByRole('heading', { name: /Ziex Client-Side keyed/i })).toBeVisible({
        timeout: 30_000,
      });
    });

    test('create 1,000 rows', async ({ page }) => {
      const ms = await timedClick(page, '#run', () => rowCount(page, 1000));
      expect(ms).toBeLessThan(500);
      console.log(`csr create 1k (DOM): ${ms.toFixed(2)}ms`);
    });

    test('update every 10th row (1k)', async ({ page }) => {
      await page.locator('#run').click();
      await expect(page.locator('tbody tr')).toHaveCount(1000);

      const ms = await timedClick(page, '#update', () => firstLabelHas(page, '!!!'));
      expect(ms).toBeLessThan(200);
      console.log(`csr update 1k (DOM): ${ms.toFixed(2)}ms`);
    });

    test('clear rows (1k)', async ({ page }) => {
      await page.locator('#run').click();
      await expect(page.locator('tbody tr')).toHaveCount(1000);

      const ms = await timedClick(page, '#clear', () => rowCount(page, 0));
      expect(ms).toBeLessThan(200);
      console.log(`csr clear 1k (DOM): ${ms.toFixed(2)}ms`);
    });

    test('swap rows (1k)', async ({ page }) => {
      await page.locator('#run').click();
      await expect(page.locator('tbody tr')).toHaveCount(1000);

      const idCell = page.locator('tbody tr').nth(1).locator('td.col-md-1').first();
      const before = await idCell.textContent();
      const ms = await timedClick(page, '#swaprows', async () => (await idCell.textContent()) !== before);
      expect(ms).toBeLessThan(200);
      console.log(`csr swap 1k (DOM): ${ms.toFixed(2)}ms`);
    });

    test('append 1,000 onto 1,000', async ({ page }) => {
      await page.locator('#run').click();
      await expect(page.locator('tbody tr')).toHaveCount(1000);

      const ms = await timedClick(page, '#add', () => rowCount(page, 2000));
      expect(ms).toBeLessThan(500);
      console.log(`csr append 1k (DOM): ${ms.toFixed(2)}ms`);
    });
  });

  test.describe('CSR performance extreme (10k)', () => {
    test.describe.configure({ mode: 'serial', timeout: 120_000 });

    test.beforeEach(async ({ page }) => {
      await page.goto('/js-framework-benchmark/csr');
      await expect(page.getByRole('heading', { name: /Ziex Client-Side keyed/i })).toBeVisible({
        timeout: 30_000,
      });
    });

    test('create 10,000 rows', async ({ page }) => {
      const ms = await timedClick(page, '#runlots', () => rowCount(page, 10_000), 60_000);
      expect(ms).toBeLessThan(5_000);
      console.log(`csr create 10k (DOM): ${ms.toFixed(2)}ms`);
    });

    test('update every 10th row (10k)', async ({ page }) => {
      await page.locator('#runlots').click();
      await expect(page.locator('tbody tr')).toHaveCount(10_000, { timeout: 60_000 });

      const ms = await timedClick(page, '#update', () => firstLabelHas(page, '!!!'), 60_000);
      expect(ms).toBeLessThan(2_000);
      console.log(`csr update 10k (DOM): ${ms.toFixed(2)}ms`);
    });

    test('append 1,000 onto 10,000', async ({ page }) => {
      await page.locator('#runlots').click();
      await expect(page.locator('tbody tr')).toHaveCount(10_000, { timeout: 60_000 });

      const ms = await timedClick(page, '#add', () => rowCount(page, 11_000), 60_000);
      expect(ms).toBeLessThan(1_000);
      console.log(`csr append 1k→10k (DOM): ${ms.toFixed(2)}ms`);
    });

    test('swap rows (10k)', async ({ page }) => {
      await page.locator('#runlots').click();
      await expect(page.locator('tbody tr')).toHaveCount(10_000, { timeout: 60_000 });

      const idCell = page.locator('tbody tr').nth(1).locator('td.col-md-1').first();
      const before = await idCell.textContent();
      const ms = await timedClick(
        page,
        '#swaprows',
        async () => (await idCell.textContent()) !== before,
        60_000,
      );
      expect(ms).toBeLessThan(2_000);
      console.log(`csr swap 10k (DOM): ${ms.toFixed(2)}ms`);
    });

    test('clear rows (10k)', async ({ page }) => {
      await page.locator('#runlots').click();
      await expect(page.locator('tbody tr')).toHaveCount(10_000, { timeout: 60_000 });

      const ms = await timedClick(page, '#clear', () => rowCount(page, 0), 60_000);
      expect(ms).toBeLessThan(2_000);
      console.log(`csr clear 10k (DOM): ${ms.toFixed(2)}ms`);
    });

    test('stress: 10k → update → append → swap → clear', async ({ page }) => {
      const createMs = await timedClick(page, '#runlots', () => rowCount(page, 10_000), 60_000);
      console.log(`  stress create 10k: ${createMs.toFixed(2)}ms`);

      const updateMs = await timedClick(page, '#update', () => firstLabelHas(page, '!!!'), 60_000);
      console.log(`  stress update 10k: ${updateMs.toFixed(2)}ms`);

      const appendMs = await timedClick(page, '#add', () => rowCount(page, 11_000), 60_000);
      console.log(`  stress append 1k: ${appendMs.toFixed(2)}ms`);

      const idCell = page.locator('tbody tr').nth(1).locator('td.col-md-1').first();
      const before = await idCell.textContent();
      const swapMs = await timedClick(
        page,
        '#swaprows',
        async () => (await idCell.textContent()) !== before,
        60_000,
      );
      console.log(`  stress swap: ${swapMs.toFixed(2)}ms`);

      const clearMs = await timedClick(page, '#clear', () => rowCount(page, 0), 60_000);
      console.log(`  stress clear: ${clearMs.toFixed(2)}ms`);

      const total = createMs + updateMs + appendMs + swapMs + clearMs;
      console.log(`csr stress pipeline (DOM): ${total.toFixed(2)}ms`);
      expect(total).toBeLessThan(12_000);
    });
  });
}

async function rowCount(page: import('@playwright/test').Page, n: number): Promise<boolean> {
  return (await page.locator('tbody tr').count()) === n;
}

async function firstLabelHas(page: import('@playwright/test').Page, needle: string): Promise<boolean> {
  const text = await page.locator('tbody tr').first().locator('td.col-md-4 a').textContent();
  return text?.includes(needle) ?? false;
}

async function timedClick(
  page: import('@playwright/test').Page,
  selector: string,
  ready: () => boolean | Promise<boolean>,
  timeout = 30_000,
): Promise<number> {
  const start = await page.evaluate(() => performance.now());
  await page.locator(selector).click();
  await expect.poll(ready, { timeout }).toBeTruthy();
  const end = await page.evaluate(() => performance.now());
  return end - start;
}
