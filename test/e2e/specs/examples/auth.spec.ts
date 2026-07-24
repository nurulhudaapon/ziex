import { test, expect } from '@playwright/test';

test.describe('Auth Example (expanded)', () => {
  test('login unlocks protected page content', async ({ page }) => {
    await page.goto('/examples/auth');

    await expect(page.getByRole('textbox', { name: /Username/ })).toBeVisible();
    await page.getByRole('textbox', { name: /Username/ }).fill('E2EUser');
    await page.getByRole('button', { name: 'Login' }).click();

    const protectedLink = page.getByRole('link', { name: /the protected page/ });
    await expect(protectedLink).toBeVisible({ timeout: 10_000 });
    await protectedLink.click();

    await expect(page).toHaveURL(/\/examples\/auth\/protected/);
    await expect(page.getByText('Super Secret Protected Content!')).toBeVisible({
      timeout: 10_000,
    });
  });

  test('protected page without login still loads route', async ({ page }) => {
    await page.goto('/examples/auth/protected');
    await expect(page).toHaveURL(/\/examples\/auth\/protected/);
  });
});
