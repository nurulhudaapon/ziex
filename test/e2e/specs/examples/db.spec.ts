import { test, expect } from '@playwright/test';

test.describe('Database Examples', () => {
  test('db page records a visit on every request', async ({ page }) => {
    await page.goto('/examples/db');
    await expect(page.getByRole('heading', { name: 'Database Example' })).toBeVisible();
    await expect(page.getByText(/Total visits recorded:\s*\d+/)).toBeVisible();

    const firstText = await page.getByText(/Total visits recorded:\s*\d+/).innerText();
    const first = Number(firstText.replace(/\D/g, ''));

    await page.reload();
    const secondText = await page.getByText(/Total visits recorded:\s*\d+/).innerText();
    const second = Number(secondText.replace(/\D/g, ''));
    expect(second).toBeGreaterThan(first);

    await expect(page.getByRole('link', { name: /Open the advance DB example/ })).toBeVisible();
  });

  test('advance db dashboard shows seeded metrics', async ({ page }) => {
    await page.goto('/examples/db/advance');

    await expect(page.getByRole('heading', { name: /Cloudflare D1 dashboard/ })).toBeVisible();
    await expect(page.getByText('Customers', { exact: true })).toBeVisible();
    await expect(page.getByText('Paid Orders', { exact: true })).toBeVisible();
    await expect(page.getByText('Revenue', { exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'What This Route Demonstrates' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Latest Snapshot' })).toBeVisible();

    // Seeded dataset should produce non-zero aggregate values.
    await expect(page.getByText('Unique customer rows in the demo dataset.')).toBeVisible();
    const customersValue = page
      .locator('p', { hasText: 'Customers' })
      .locator('xpath=following-sibling::p[1]');
    await expect(customersValue).not.toHaveText('0');
  });
});
