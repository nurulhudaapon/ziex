import { test, expect } from '@playwright/test';

if (process.env.TEMPLATE_TESTS) {
  test.describe('Template Home UI and Navigation', () => {
    test('Internal routing between Home and About works and returns cleanly', async ({ page }) => {
      // 1. From home page, click 'Navigate to About Page'.
      await page.goto('http://localhost:3000/');
      await page.getByRole('link', { name: 'Navigate to About Page' }).click();
      await expect(page).toHaveURL(/\/about$/);
      await expect(page.getByRole('heading', { name: 'Ziex' })).toBeVisible();
      await expect(page.getByRole('link', { name: 'Back to Home' })).toBeVisible();

      // 2. Click 'Back to Home'.
      await page.getByRole('link', { name: 'Back to Home' }).click();
      await expect(page).toHaveURL(/\/$/);
      await expect(page.getByRole('button', { name: 'Reset' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Decrement' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Increment' })).toBeVisible();
    });
  });
}