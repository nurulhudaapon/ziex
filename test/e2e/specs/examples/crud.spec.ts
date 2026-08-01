import { test, expect } from '@playwright/test';

test.describe('CRUD Task Manager Example', () => {
  test('page loads task manager shell and accepts input', async ({ page }) => {
    await page.goto('/examples/crud');

    await expect(page.getByRole('heading', { name: 'Task manager' })).toBeVisible();
    await expect(page.getByText('Full-stack CRUD demonstration with Ziex')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Add Task' })).toBeVisible();
    await expect(page.getByPlaceholder('What needs to be done?')).toBeVisible();
    await expect(page.getByRole('columnheader', { name: 'Done' })).toBeVisible();
    await expect(page.getByRole('columnheader', { name: 'Task' })).toBeVisible();

    const title = `e2e-task-${Date.now()}`;
    await page.getByPlaceholder('What needs to be done?').fill(title);
    await expect(page.getByPlaceholder('What needs to be done?')).toHaveValue(title);
  });

  test('empty title is blocked by required validation', async ({ page }) => {
    await page.goto('/examples/crud');
    await page.waitForLoadState('networkidle');
    
    const before = await page.locator('tbody tr').count();

    await page.getByRole('button', { name: 'Add Task' }).click();
    await page.waitForTimeout(300);

    const after = await page.locator('tbody tr').count();
    expect(after).toBe(before);
    await expect(page.getByPlaceholder('What needs to be done?')).toBeFocused();
  });
});
