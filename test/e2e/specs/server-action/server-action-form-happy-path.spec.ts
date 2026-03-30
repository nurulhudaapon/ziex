
import { test, expect } from '@playwright/test';
// spec: .playwright-mcp/spec/server-action.plan.md

test.describe('Form and Event Actions', () => {
  test('Form submissions and event actions (happy path)', async ({ page }) => {
    // Navigate to the Server Action example page to begin test execution for Form and Event Actions suite.
    await page.goto('http://localhost:3000/examples/server-action');

    // Enter valid username in first block for login test.
    await page.getByRole('textbox', { name: 'Username:' }).first().fill('testuser');

    // Click 'Login' in first block to process login and check server log.
    await page.getByRole('button', { name: 'Login' }).first().click();

    // Click 'Client Event' in first block to check browser console log.
    await page.getByRole('button', { name: 'Client Event' }).first().click();

    // Click 'Server Event' in first block to check server log.
    await page.getByRole('button', { name: 'Server Event' }).first().click();

    // Click 'Submit' in first form (name/id) in first block to process form and check server log.
    await page.getByRole('button', { name: 'Submit' }).first().click();

    // Click 'Submit' in second form (name/id) in first block to process form and check server log.
    await page.getByRole('button', { name: 'Submit' }).nth(1).click();
  });
});
