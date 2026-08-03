// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';

test.describe('Async Timer Example', () => {
  test('Timer and Interval Functionality', async ({ page }) => {
    await page.goto('/examples/async');

    await expect(page.getByRole('button', { name: 'setTimeout (2s)' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Start Interval (1s)' })).toBeVisible();

    await page.getByRole('button', { name: 'setTimeout (2s)' }).click();
    await expect(page.getByText('Status: Waiting for timeout')).toBeVisible();
    await expect(page.getByText('Status: Timeout complete')).toBeVisible({ timeout: 3_000 });

    await page.getByRole('button', { name: 'Start Interval (1s)' }).click();
    await expect(page.getByText('Interval ticks: 2')).toBeVisible({ timeout: 3_500 });

    await page.getByRole('button', { name: 'Reset' }).click();
    await expect(page.getByText('Status: Ready')).toBeVisible();
    await expect(page.getByText('Interval ticks: 0')).toBeVisible();
  });
});
