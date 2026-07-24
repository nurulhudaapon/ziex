import { test, expect } from '@playwright/test';

test.describe('Hydration Example (expanded)', () => {
  test('renders all hydration test sections and prop values', async ({ page }) => {
    await page.goto('/examples/wasm/hydration');

    await expect(page.getByRole('heading', { name: 'Hydration Demo' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Test 1: Basic types' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Test 2: Negative' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Test 3: Floats' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Test 4: Strings' })).toBeVisible();

    await expect(page.getByText('Inidtial: 42')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Inidtial: -100')).toBeVisible();
    await expect(page.getByText('Negative: -999')).toBeVisible();
    await expect(page.getByText('Float: 3.14').first()).toBeVisible();
    await expect(page.getByText('Label: Hello World')).toBeVisible();
    await expect(page.getByText('Counter Component Test').first()).toBeVisible();
    await expect(page.getByText('Shared: true').first()).toBeVisible();
    await expect(page.getByText('Nested Value: 123').first()).toBeVisible();
  });
});
