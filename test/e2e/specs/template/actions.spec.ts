import { test, expect } from '@playwright/test';

if (process.env.TEMPLATE_TESTS){
test.describe('Template Home UI and Navigation', () => {
  test('Counter supports increment, decrement, and reset from any numeric state', async ({ page }) => {
    // 1. Capture initial counter value (do not hardcode, treat as dynamic baseline).
    await page.goto('http://localhost:3000/');
    const counter = page.locator('main h5');
    const baseline = Number((await counter.textContent()) ?? 'NaN');
    expect(Number.isInteger(baseline)).toBeTruthy();

    // 2. Click Increment once.
    await page.getByRole('button', { name: 'Increment' }).click();
    const afterIncrement = Number((await counter.textContent()) ?? 'NaN');
    expect(afterIncrement).toBe(baseline + 1);

    // 3. Click Decrement twice.
    await page.getByRole('button', { name: 'Decrement' }).click();
    await page.getByRole('button', { name: 'Decrement' }).click();
    const afterTwoDecrements = Number((await counter.textContent()) ?? 'NaN');
    expect(afterTwoDecrements).toBe(afterIncrement - 2);

    // 4. Click Reset.
    await page.getByRole('button', { name: 'Reset' }).click();
    await expect(counter).toHaveText('0');

    // 5. Click Decrement repeatedly (for example 10-15 times).
    for (let i = 0; i < 12; i++) {
      await page.getByRole('button', { name: 'Decrement' }).click();
    }

    const negativeValue = Number((await counter.textContent()) ?? 'NaN');
    expect(negativeValue).toBeLessThan(0);
    await expect(page.getByRole('button', { name: 'Increment' })).toBeVisible();
  });
});
}

