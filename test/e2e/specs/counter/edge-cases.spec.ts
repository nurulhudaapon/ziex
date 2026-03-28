// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

test.describe('Counter Example', () => {
  test('Multiple Rapid Clicks', async ({ page }) => {
    // 1. Navigate to /examples/wasm/simple
    await page.goto(`${BASE_URL}/examples/wasm/simple`);
    // 2. Click 'State + 4' button rapidly 10 times
    const stateButtons = await page.getByRole('button', { name: /State \+ \d+/ }).all();
    for (let i = 0; i < 10; i++) {
      await stateButtons[0].click();
    }
    // Optionally, assert the state value increased by 40
  });
});
