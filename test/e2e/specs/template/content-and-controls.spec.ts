import { test, expect } from '@playwright/test';
if (process.env.TEMPLATE_TESTS) {

  test.describe('Template Home UI and Navigation', () => {
    test('Home page renders critical content and controls', async ({ page }) => {
      // 1. Navigate to http://localhost:3000/ from a fresh browser context.
      await page.goto('http://localhost:3000/');

      // 2. Locate primary calls-to-action and controls.
      await expect(page).toHaveTitle('Ziex');
      await expect(page.getByRole('heading', { name: 'Ziex' })).toBeVisible();
      await expect(page.getByText('Ziex is a framework for building web applications with Zig.')).toBeVisible();

      const docsLink = page.getByRole('link', { name: 'See Ziex Docs →' });
      await expect(docsLink).toBeVisible();
      await expect(docsLink).toHaveAttribute('href', 'https://ziex.dev');

      await expect(page.getByRole('button', { name: 'Reset' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Decrement' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Increment' })).toBeVisible();

      const value = Number((await page.locator('main h5').textContent()) ?? 'NaN');
      expect(Number.isInteger(value)).toBeTruthy();

      const aboutLink = page.getByRole('link', { name: 'Navigate to About Page' });
      await expect(aboutLink).toBeVisible();
      await expect(aboutLink).toHaveAttribute('href', '/about');
    });
  });
}
