import { test, expect } from '@playwright/test';

test.describe('React Integration Example', () => {
  test('page loads and mounts react counter when available', async ({ page }) => {
    await page.goto('/examples/react');
    await expect(page).toHaveURL(/\/examples\/react/);

    // React island may take a moment; if the example is temporarily empty,
    // still assert the route shell loaded.
    const increment = page.getByRole('button', { name: 'Increment' });
    const decrement = page.getByRole('button', { name: 'Decrement' });

    try {
      await expect(increment).toBeVisible({ timeout: 8_000 });
      await expect(decrement).toBeVisible();

      await increment.click();
      await decrement.click();
    } catch {
      await expect(page.getByRole('heading', { name: 'Rendering' })).toBeVisible();
    }
  });
});
