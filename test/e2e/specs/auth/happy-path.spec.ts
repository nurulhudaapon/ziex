// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

test.describe('Auth Example', () => {
  test('Login and Protected Page', async ({ page }) => {
    // 1. Navigate to /examples/auth
    await page.goto('/examples/auth');
    // expect: Auth UI loads with username input and login button.
    await expect(page.getByRole('textbox', { name: /Username/ })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Login' })).toBeVisible();
    // 2. Enter username and click 'Login'
    await page.getByRole('textbox', { name: /Username/ }).fill('TestUser');
    await page.getByRole('button', { name: 'Login' }).click();
    // 3. Click 'the protected page' link
    await page.getByRole('link', { name: /the protected page/ }).click();
    // Optionally, assert protected page is accessible
  });
});
