// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';


test.describe('Counter Example', () => {
  test('increments, decrements, resets, and updates derived output', async ({ page }) => {
    await page.goto('/examples/counter');

    await expect(page.getByRole('heading', { name: 'Count: 0' })).toBeVisible();
    await expect(page.getByText('Doubled: 0')).toBeVisible();

    await page.getByRole('button', { name: 'Increment' }).click();
    await expect(page.getByRole('heading', { name: 'Count: 1' })).toBeVisible();
    await expect(page.getByText('Doubled: 2')).toBeVisible();
    await expect(page.getByText('Sign: positive')).toBeVisible();

    await page.getByRole('button', { name: 'Decrement' }).click();
    await page.getByRole('button', { name: 'Decrement' }).click();
    await expect(page.getByText('Sign: negative')).toBeVisible();

    await page.getByRole('button', { name: 'Reset' }).click();
    await expect(page.getByRole('heading', { name: 'Count: 0' })).toBeVisible();
  });
});
