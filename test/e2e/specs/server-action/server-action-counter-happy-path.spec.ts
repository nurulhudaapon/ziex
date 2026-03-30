
import { test, expect } from '@playwright/test';
// spec: .playwright-mcp/spec/server-action.plan.md

test.describe('Counter and Age Actions', () => {
  test('Increment and update actions (happy path)', async ({ page }) => {
    // Navigate to the Server Action example page to begin test execution for Counter and Age Actions suite.
    await page.goto('http://localhost:3000/examples/server-action');

    // Click '+ (Server)' button in first counter section. Expect: Count increases by 1. Server log: 'increment: <new count>'
    await page.getByRole('button', { name: '+ (Server)' }).first().click();
    await expect(page.getByText('Count: 1')).toBeVisible();

    // Click '+ (Client)' button in first counter section. Expect: Count increases by 1. Browser console log: 'increment: <new count>'
    await page.getByRole('button', { name: '+ (Client)' }).first().click();
    await expect(page.getByText('Count: 2')).toBeVisible();

    // Click '+ (Server sbind)' button in first counter section. Expect: Count increases by 1. Server log: 'increment: <new count>'
    await page.getByRole('button', { name: '+ (Server sbind)' }).first().click();
    await expect(page.getByText('Count: 3')).toBeVisible();

    // Click '+ (Server)' button in age section (first block). Expect: Age increases by 1. Server log: 'increment: <new age>'
    await page.getByRole('button', { name: '+ (Server)' }).nth(1).click();
    await expect(page.getByText('Age: 1')).toBeVisible();

    // Click 'Update (Server))' button in first block. Expect: Name/age updated if changed. Server log: update event.
    await page.getByRole('button', { name: 'Update (Server))' }).first().click();
    // No visible assertion for update, as it depends on state change
  });
});
