import { test, expect } from '@playwright/test';
import { skipOnRemoteStatic } from '../../helpers/env';

test.describe('Database Examples', () => {
  test('db page records a visit on every request', async ({ page }) => {
    test.skip(skipOnRemoteStatic, 'Static deploy cannot persist DB writes across reloads');
    await page.goto('/examples/db');
    await expect(page.getByRole('heading', { name: 'Database Example' })).toBeVisible();
    await expect(page.getByText(/Total visits recorded:\s*\d+/)).toBeVisible();

    const firstText = await page.getByText(/Total visits recorded:\s*\d+/).innerText();
    const first = Number(firstText.replace(/\D/g, ''));

    await page.reload();
    const secondText = await page.getByText(/Total visits recorded:\s*\d+/).innerText();
    const second = Number(secondText.replace(/\D/g, ''));
    expect(second).toBeGreaterThan(first);

    await expect(page.getByRole('heading', { name: 'Aggregate query' })).toBeVisible();
  });

  test('db page shows seeded aggregate metrics', async ({ page }) => {
    await page.goto('/examples/db');

    await expect(page.getByText('Customers', { exact: true })).toBeVisible();
    await expect(page.getByText('Paid orders', { exact: true })).toBeVisible();
    await expect(page.getByText('Revenue', { exact: true })).toBeVisible();

    // Seeded dataset should produce non-zero aggregate values.
    const customersValue = page
      .locator('dt', { hasText: 'Customers' })
      .locator('xpath=following-sibling::dd[1]');
    await expect(customersValue).not.toHaveText('0');
  });
});
