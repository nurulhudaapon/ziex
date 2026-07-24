import { test, expect } from '@playwright/test';

test.describe('Examples Overview', () => {
  test('index page shows control-flow sections and previews', async ({ page }) => {
    await page.goto('/examples');

    await expect(page.getByRole('heading', { level: 1, name: 'Examples' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'If/Else Statements' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Switch Expressions' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'For Loop' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Component Props' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Dynamic Attributes' })).toBeVisible();

    await expect(page.locator('#if-else')).toBeVisible();
    await expect(page.locator('#switch')).toBeVisible();
    await expect(page.locator('#for-loop')).toBeVisible();
    await expect(page.locator('#components')).toBeVisible();
    await expect(page.locator('#dynamic-attributes')).toBeVisible();
  });

  test('sidebar links navigate to example applications', async ({ page }) => {
    await page.goto('/examples');

    await page.getByRole('link', { name: 'Counter', exact: true }).click();
    await expect(page).toHaveURL(/\/examples\/wasm\/simple/);

    await page.goto('/examples');
    await page.getByRole('link', { name: 'Todo App' }).click();
    await expect(page).toHaveURL(/\/examples\/wasm$/);

    await page.goto('/examples');
    await page.getByRole('link', { name: 'Auth', exact: true }).click();
    await expect(page).toHaveURL(/\/examples\/auth/);
  });

  test('overview page renders QuickExample content', async ({ page }) => {
    await page.goto('/examples/overview');
    await expect(page.getByText(/Hello,\s*ZX\s*Dev!/i)).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('John')).toBeVisible();
    await expect(page.getByText('Jane')).toBeVisible();
  });
});
