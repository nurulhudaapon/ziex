// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';


test.describe('Streaming Example', () => {
  test('Streaming Content Loads', async ({ page }) => {
    // 1. Navigate to /examples/streaming
    await page.goto('/examples/streaming');
    // expect: All sections (Instant Content, User Profile, Recent Posts, Site Statistics) are visible.
    await expect(page.getByRole('heading', { name: 'Instant Content' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'User Profile' })).toBeVisible();
    await expect(page.getByRole('heading', { name: /Recent Posts/ })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Site Statistics' })).toBeVisible();
  });
});
