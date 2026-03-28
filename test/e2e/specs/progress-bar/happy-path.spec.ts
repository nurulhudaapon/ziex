// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

test.describe('Progress Bar Example', () => {
  test('Progress Bar Controls', async ({ page }) => {
    // 1. Navigate to /examples/wasm/progress
    await page.goto(`${BASE_URL}/examples/wasm/progress`);
    // expect: Progress bar and control buttons are visible.
    await expect(page.getByRole('button', { name: 'Start' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Stop' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Reset' })).toBeVisible();
    // 2. Click 'Start' and observe progress
    await page.getByRole('button', { name: 'Start' }).click();
    await page.waitForTimeout(1000);
    // 3. Click 'Stop'
    await page.getByRole('button', { name: 'Stop' }).click();
    // 4. Click 'Reset'
    await page.getByRole('button', { name: 'Reset' }).click();
    // Optionally, assert progress resets to 0%
  });
});
