import { test, expect } from '@playwright/test';

test.describe('Event.as() Example', () => {
  test('page loads typed-event demo controls', async ({ page }) => {
    await page.goto('/examples/event');

    await expect(page.getByRole('heading', { name: /Event\.as\(\) type-safety demo/ })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Click me' })).toBeVisible();
    await expect(page.getByPlaceholder('Type here')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Submit form' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Read as generic Event' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Trigger type mismatch' })).toBeVisible();
  });

  test('pointer, keyboard, input, submit, and catch-all handlers stay interactive', async ({ page }) => {
    await page.goto('/examples/event');

    await page.getByRole('button', { name: 'Click me' }).click();

    const input = page.getByPlaceholder('Type here');
    await input.click();
    await input.type('ab');

    await page.getByRole('button', { name: 'Submit form' }).click();
    await expect(page).toHaveURL(/\/examples\/event/);

    await page.getByRole('button', { name: 'Read as generic Event' }).click();

    // Mismatch button is intentional for debug panics; only assert it remains clickable
    // without requiring a crash in this release build.
    await expect(page.getByRole('button', { name: 'Trigger type mismatch' })).toBeEnabled();
  });
});
