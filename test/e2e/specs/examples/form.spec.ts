import { test, expect } from '@playwright/test';

test.describe('Form Example (expanded)', () => {
  test('add user and find them via search', async ({ page }) => {
    await page.goto('/examples/form');

    const unique = `User-${Date.now()}`;
    await expect(page.getByRole('textbox', { name: /Name/ })).toBeVisible();
    await page.getByRole('textbox', { name: /Name/ }).fill(unique);
    await page.getByRole('button', { name: 'Add User' }).click();
    await expect(page.getByText(unique)).toBeVisible({ timeout: 10_000 });

    await page.getByRole('textbox', { name: /Search users/ }).fill(unique);
    await page.getByRole('button', { name: 'Search' }).click();
    await expect(page.getByText(unique)).toBeVisible({ timeout: 10_000 });
  });
});
