
import { test, expect } from '@playwright/test';
// spec: .playwright-mcp/spec/server-action.plan.md

test.describe('Negative and Edge Cases', () => {
  test('Edge and negative scenarios', async ({ page }) => {
    // Navigate to the Server Action example page to begin test execution for Negative and Edge Cases suite.
    await page.goto('http://localhost:3000/examples/server-action');

    // Click all increment and event buttons rapidly in succession to check for errors and race conditions.
    await page.getByRole('button', { name: '+ (Server)' }).first().click();
    await page.getByRole('button', { name: '+ (Server sbind)' }).first().click();
    await page.getByRole('button', { name: '+ (Server)' }).nth(1).click();
    await page.getByRole('button', { name: 'Update (Server))' }).first().click();
    await page.getByRole('button', { name: 'Client Event' }).first().click();
    await page.getByRole('button', { name: '+ (Client)' }).first().click();
    await page.getByRole('button', { name: 'Server Event' }).first().click();
    await page.getByRole('button', { name: '+ (Server)' }).nth(2).click();
    await page.getByRole('button', { name: '+ (Client)' }).nth(1).click();
    await page.getByRole('button', { name: '+ (Server)' }).nth(3).click();
    await page.getByRole('button', { name: 'Update (Server))' }).nth(1).click();
    await page.getByRole('button', { name: 'Client Event' }).nth(1).click();
    await page.getByRole('button', { name: '+ (Server sbind)' }).nth(1).click();
    await page.getByRole('button', { name: 'Server Event' }).nth(1).click();

    // Submit forms with empty required fields to check for validation error or server log with empty values.
    await page.getByRole('button', { name: 'Submit' }).first().click();
    await page.getByRole('button', { name: 'Submit' }).nth(1).click();
    await page.getByRole('button', { name: 'Submit' }).nth(2).click();
    await page.getByRole('button', { name: 'Submit' }).nth(3).click();

    // Enter invalid data (non-numeric) in ID field and submit form to check for validation error or server log with invalid data.
    await page.getByRole('textbox', { name: 'ID:' }).first().fill('invalid-id');
    await page.getByRole('button', { name: 'Submit' }).first().click();

    // Enter very long input in Name field and submit form to check for graceful handling.
    await page.getByRole('textbox', { name: 'Name:' }).nth(1).fill('aVeryLongNameValueThatExceedsNormalLength1234567890');
    await page.getByRole('textbox', { name: 'ID:' }).first().fill('9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999');
    await page.getByRole('button', { name: 'Submit' }).first().click();

    // Check all buttons for enabled state.
    const allButtonsEnabled = await page.evaluate(() => Array.from(document.querySelectorAll('button')).every(btn => !btn.disabled));
    expect(allButtonsEnabled).toBe(true);

    // Check all inputs for enabled and not read-only state.
    const allInputsEnabled = await page.evaluate(() => Array.from(document.querySelectorAll('input')).every(input => !input.disabled && !input.readOnly));
    expect(allInputsEnabled).toBe(true);
  });
});
