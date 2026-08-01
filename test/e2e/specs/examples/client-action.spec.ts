import { test, expect } from '@playwright/test';

test.describe('Client Action Example', () => {
  test('click increments stateful counter', async ({ page }) => {
    await page.goto('/examples/client-action');
    await page.waitForLoadState('networkidle');

    const button = page.getByRole('button', { name: /Click Me \d+/ });
    await expect(button).toBeVisible();
    await expect(button).toHaveText(/Click Me 1/);

    await button.click();
    await expect(button).toHaveText(/Click Me 2/);

    await button.click();
    await expect(button).toHaveText(/Click Me 3/);
  });

  test('client form action increments counter from shared state', async ({ page }) => {
    await page.goto('/examples/client-action');
    await page.waitForLoadState('networkidle');
    
    const button = page.getByRole('button', { name: /Click Me \d+/ });
    await expect(button).toHaveText(/Click Me 1/);

    const input = page.locator('input[name="message"]');
    await expect(input).toHaveValue('hello');
    await input.fill('from-e2e');

    await page.getByRole('button', { name: 'Submit' }).click();
    await expect(button).toHaveText(/Click Me 2/);
  });
});
