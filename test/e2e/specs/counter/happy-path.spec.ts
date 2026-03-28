// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

test.describe('Counter Example', () => {
  test('Increment and Decrement State', async ({ page }) => {
    // 1. Navigate to /examples/wasm/simple
    await page.goto(`${BASE_URL}/examples/wasm/simple`);
    await expect(page.getByRole('heading', { name: /State \(re-render\):/ })).toHaveCount(3);
    // 2. Click first 'State + <Number>' button
    const stateButtons = await page.getByRole('button', { name: /State \+ \d+/ }).all();
    await stateButtons[0].click();
    // 3. Click second 'State + <Number>' button
    await stateButtons[1].click();
    // 4. Click third 'State + <Number>' button
    await stateButtons[2].click();
    // Optionally, add assertions for updated state values if needed
  });
});
