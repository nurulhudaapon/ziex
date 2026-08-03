// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

test.describe('Counter Example', () => {
  test('Multiple Rapid Clicks', async ({ page }) => {
    await page.goto('/examples/counter');

    const increment = page.getByRole('button', { name: 'Increment' });
    for (let i = 0; i < 10; i++) {
      await increment.click();
    }

    await expect(page.getByRole('heading', { name: 'Count: 10' })).toBeVisible();
    await expect(page.getByText('Doubled: 20')).toBeVisible();
  });
});
