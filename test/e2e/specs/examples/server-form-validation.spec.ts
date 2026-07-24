import { test, expect } from '@playwright/test';
import { skipOnRemoteStatic } from '../../helpers/env';

test.describe('Server Form Validation Example', () => {
  test('rejects invalid id and accepts valid id', async ({ page }) => {
    test.skip(skipOnRemoteStatic, 'Static deploy has no live server form handlers');
    await page.goto('/examples/server-form-validation');

    await expect(page.getByText('Please log in')).toBeVisible();

    await page.getByPlaceholder('Name').fill('Ziex');
    await page.getByPlaceholder('ID').fill('0');
    await page.getByRole('button', { name: 'Submit' }).click();
    await expect(page.getByText('ID must be between 1 and 100')).toBeVisible({ timeout: 10_000 });

    await page.getByPlaceholder('ID').fill('101');
    await page.getByRole('button', { name: 'Submit' }).click();
    await expect(page.getByText('ID must be between 1 and 100')).toBeVisible({ timeout: 10_000 });

    await page.getByPlaceholder('Name').fill('Grace');
    await page.getByPlaceholder('ID').fill('7');
    await page.getByRole('button', { name: 'Submit' }).click();
    await expect(page.getByText('Hello, Grace! (7)')).toBeVisible({ timeout: 10_000 });
  });
});
