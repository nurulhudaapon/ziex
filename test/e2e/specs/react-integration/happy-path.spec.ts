// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

test.describe('React Integration Example', () => {
  test('Increment and Decrement Visit Count', async ({ page }) => {
    // 1. Navigate to /examples/wasm/react
    await page.goto(`${BASE_URL}/examples/wasm/react`);
    // expect: Page loads with Increment and Decrement buttons and visit count.
    await expect(page.getByRole('button', { name: 'Increment' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Decrement' })).toBeVisible();
    // 2. Click 'Increment'
    await page.getByRole('button', { name: 'Increment' }).click();
    // 3. Click 'Decrement'
    await page.getByRole('button', { name: 'Decrement' }).click();
    // Optionally, assert visit count changes
  });
});
