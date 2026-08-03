import { test, expect } from '@playwright/test';

test.describe('Hydration Example', () => {
  test('hydrates typed props and updates client state', async ({ page }) => {
    await page.goto('/examples/hydration');

    await expect(page.getByRole('heading', { name: 'Hydration', exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Hydrated counter' })).toBeVisible();
    await expect(page.getByText('Initial prop: 42')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Enabled: true')).toBeVisible();
    await expect(page.getByText('Metadata: server v1')).toBeVisible();

    const counter = page.getByRole('button', { name: 'Count: 42' });
    await counter.click();
    await expect(page.getByRole('button', { name: 'Count: 43' })).toBeVisible();
  });
});
