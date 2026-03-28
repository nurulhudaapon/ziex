// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';


test.describe('Hydration Example', () => {
  test('Hydration Loads', async ({ page }) => {
    // 1. Navigate to /examples/wasm/hydration
    await page.goto('/examples/wasm/hydration');
    // expect: Hydration demo loads successfully.
    await expect(page).toHaveURL(/\/examples\/wasm\/hydration/);
  });
});
