// spec: specs/examples-applications.plan.md
// seed: seed.spec.ts

import { test, expect } from '@playwright/test';


test.describe('Todo App Example', () => {
  test('Add and Remove Todos', async ({ page }) => {
    // 1. Navigate to /examples/wasm
    await page.goto('/examples/wasm');
    // expect: Todo app loads with initial todos.
    await expect(page.getByRole('textbox', { name: /Add a new todo/ })).toBeVisible();
    // 2. Type 'Test new todo' in the input and click 'Add'
    await page.getByRole('textbox', { name: /Add a new todo/ }).fill('Test new todo');
    await page.getByRole('button', { name: 'Add' }).click();
    await expect(page.getByText('Test new todo')).toBeVisible();
    // 3. Click '×' on a todo item
    const removeButton = page.getByRole('button', { name: /×/ }).first();
    await removeButton.click();
    // Optionally, assert the todo is removed
  });
});
