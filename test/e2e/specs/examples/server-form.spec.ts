import { test, expect } from '@playwright/test';
import { skipOnRemoteStatic } from '../../helpers/env';

test.describe('Server Form Example', () => {
  test('login form submit updates greeting message', async ({ page }) => {
    test.skip(skipOnRemoteStatic, 'Static deploy has no live server form handlers');
    await page.goto('/examples/server-form');

    await expect(page.getByText('Please log in')).toBeVisible();
    await page.getByPlaceholder('Enter name').fill('Ada Lovelace');
    await page.getByPlaceholder('Enter ID').fill('42');
    await page.getByRole('button', { name: 'Submit' }).click();

    await expect(page.getByText('Hello, Ada Lovelace!')).toBeVisible({ timeout: 10_000 });
  });

  test('server event click increments counter button', async ({ page }) => {
    test.skip(skipOnRemoteStatic, 'Static deploy has no live server event handlers');
    await page.goto('/examples/server-form');
    
    const button = page.getByRole('button', { name: /Click Me \d+/ });
    await expect(button).toHaveText(/Click Me 1/);
    await button.click();
    await expect(button).toHaveText(/Click Me 2/, { timeout: 10_000 });
  });
});
