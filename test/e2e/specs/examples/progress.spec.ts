import { test, expect } from '@playwright/test';

test.describe('Progress Bar Example (expanded)', () => {
  test('start, stop, and reset progress controls', async ({ page }) => {
    await page.goto('/examples/wasm/progress');

    const start = page.getByRole('button', { name: /Start/i }).first();
    const stop = page.getByRole('button', { name: /Stop/i }).first();
    const reset = page.getByRole('button', { name: /Reset/i }).first();

    await expect(start).toBeVisible({ timeout: 15_000 });
    await expect(stop).toBeVisible();
    await expect(reset).toBeVisible();

    await start.click();
    await page.waitForTimeout(500);
    await stop.click();
    await reset.click();
  });
});
