import { test, expect } from '@playwright/test';
import { skipOnRemoteStatic } from '../../helpers/env';

test.describe('KV Example', () => {
  test('server visit count increments across reloads', async ({ page }) => {
    test.skip(skipOnRemoteStatic, 'Static deploy cannot persist KV writes across reloads');
    await page.goto('/examples/kv');
    await expect(page.getByText(/Visit count:\s*\d+/)).toBeVisible();

    const firstText = await page.getByText(/Visit count:\s*\d+/).innerText();
    const first = Number(firstText.replace(/\D/g, ''));

    await page.reload();
    const secondText = await page.getByText(/Visit count:\s*\d+/).innerText();
    const second = Number(secondText.replace(/\D/g, ''));

    expect(second).toBeGreaterThan(first);
  });

  test('client controls stay interactive', async ({ page }) => {
    await page.goto('/examples/kv');

    const clientBtn = page.getByRole('button', { name: /Client count:/ });
    await expect(clientBtn).toBeVisible();
    await clientBtn.click();

    const input = page.getByPlaceholder('Type here to test generated events');
    await expect(input).toBeVisible();
    await input.click();
    await input.type('kv');
    await page.getByRole('button', { name: 'Submit Test Form' }).click();
    await expect(page).toHaveURL(/\/examples\/kv/);
  });
});
