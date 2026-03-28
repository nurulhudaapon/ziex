// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

test.describe('Form Example', () => {
  test('Add and Search Users', async ({ page }) => {
    // 1. Navigate to /examples/form
    await page.goto(`${BASE_URL}/examples/form`);
    // expect: Form UI loads with search and add user fields.
    await expect(page.getByRole('textbox', { name: /Search users/ })).toBeVisible();
    await expect(page.getByRole('textbox', { name: /Name/ })).toBeVisible();
    // 2. Type a name and click 'Add User'
    await page.getByRole('textbox', { name: /Name/ }).fill('TestUser');
    await page.getByRole('button', { name: 'Add User' }).click();
    // Optionally, assert user is added
    // 3. Type a name in 'Search users...' and click 'Search'
    await page.getByRole('textbox', { name: /Search users/ }).fill('TestUser');
    await page.getByRole('button', { name: 'Search' }).click();
    // Optionally, assert matching users are displayed
  });
});
