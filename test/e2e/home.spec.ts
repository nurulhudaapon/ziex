import { test, expect } from '@playwright/test';

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

test('has title', async ({ page }) => {
  await page.goto(BASE_URL + '/');

  // Expect a title "to contain" a substring.
  await expect(page).toHaveTitle(/Ziex/);
});

test('get started link', async ({ page }) => {
  await page.goto(BASE_URL + '/');

  // Click the get started link.
  await page.getByRole('link', { name: 'Get started' }).click();

  // Expects page to have a heading with the name of Installation.
  // await expect(page.getByRole('heading', { name: 'Installation' })).toBeVisible();
});
