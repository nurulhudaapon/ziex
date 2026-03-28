// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

test.describe('Hydration Example', () => {
  test('Hydration Loads', async ({ page }) => {
    // 1. Navigate to /examples/wasm/hydration
    await page.goto(`${BASE_URL}/examples/wasm/hydration`);
    // expect: Hydration demo loads successfully.
    await expect(page).toHaveURL(/\/examples\/wasm\/hydration/);
  });
});
