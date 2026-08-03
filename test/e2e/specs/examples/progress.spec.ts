import { test, expect } from '@playwright/test';
import { skipOnRemoteStatic } from '../../helpers/env';

test.describe('Progress Bar Example (expanded)', () => {
  test('start, stop, and reset progress controls', async ({ page }) => {
    test.skip(skipOnRemoteStatic, 'Wasm progress controls are not fully available on static deploy');
    await page.goto('/examples/progress');
   
    
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
