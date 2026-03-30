// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';


test.describe('Progress Bar Example', () => {
  test('Progress Bar Controls', async ({ page }) => {
    // 1. Navigate to /examples/wasm/progress
    await page.goto('/examples/wasm/progress');
    // expect: Progress bar and control buttons are visible.
    await expect(page.getByRole('button', { name: 'Start' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Stop' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Reset' })).toBeVisible();
    // 2. Click 'Start' and observe progress
    await page.getByRole('button', { name: 'Start' }).click();
    // Wait for Stop button to become enabled (progress started)
    const stopButton = page.getByRole('button', { name: 'Stop' });
    await stopButton.waitFor({ state: 'visible' });
    await page.waitForFunction(() => {
      const btn = Array.from(document.querySelectorAll('button')).find(b => b.textContent?.trim() === 'Stop');
      return btn && !btn.disabled;
    });
    await stopButton.click();
    // Wait for Reset button to become enabled (if it can be disabled)
    const resetButton = page.getByRole('button', { name: 'Reset' });
    await resetButton.waitFor({ state: 'visible' });
    await page.waitForFunction(() => {
      const btn = Array.from(document.querySelectorAll('button')).find(b => b.textContent?.trim() === 'Reset');
      return btn && !btn.disabled;
    });
    await resetButton.click();
    // Optionally, assert progress resets to 0%
  });
});
