// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';


test.describe('Streaming Example', () => {
  test('Streaming Content Loads', async ({ page }) => {
    // 1. Navigate to /examples/streaming
    //TODO:  navigate to the page without waiting for the page to load
    await page.goto('/examples/streaming')
    // expect: All sections (Instant Content, User Profile, Recent Posts, Site Statistics) are visible.
    await expect(page.getByRole('heading', { name: 'User Profile' })).toBeVisible();

    // TODO: this should be streamed first and we can check
    // await expect(page.getByRole('heading', { name: 'Recent Posts (.....)'})).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Site Statistics' })).toBeVisible();

    // Wait for the full page load complete
    await page.waitForLoadState('networkidle');
    await expect(page.getByRole('heading', { name: 'Recent Posts (3)' })).toBeVisible();
  ;
  });
});
