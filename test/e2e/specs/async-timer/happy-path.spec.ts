// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

test.describe('Async Timer Example', () => {
  test('Timer and Interval Functionality', async ({ page }) => {
    // 1. Navigate to /examples/wasm/async
    await page.goto('/examples/wasm/async');
    // expect: Timer demo loads with timer and interval buttons.
    await expect(page.getByRole('button', { name: 'setTimeout (2s)' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Start Interval (1s)' })).toBeVisible();
    // 2. Click 'setTimeout (2s)' and wait 2 seconds
    await page.getByRole('button', { name: 'setTimeout (2s)' }).click();
    await page.waitForTimeout(2100);
    // 3. Click 'Start Interval (1s)' and wait 3 seconds
    await page.getByRole('button', { name: 'Start Interval (1s)' }).click();
    await page.waitForTimeout(3100);
    // Optionally, assert interval ticks increased
  });
});
