import { test, expect } from '@playwright/test';
import path from 'path';
import fs from 'fs';
import os from 'os';

test.describe('File Form Example', () => {
  test('uploads an image and shows name + preview', async ({ page }) => {
    await page.goto('/examples/form/file');

    await expect(page.getByRole('button', { name: 'Submit' })).toBeVisible();
    await expect(page.locator('input[name="name"]')).toBeVisible();
    await expect(page.locator('input[name="picture"]')).toBeVisible();

    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ziex-e2e-'));
    const filePath = path.join(tmpDir, 'avatar.png');
    // 1x1 transparent PNG
    const png = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5W2fQAAAAASUVORK5CYII=',
      'base64',
    );
    fs.writeFileSync(filePath, png);

    await page.locator('input[name="name"]').fill('E2E User');
    await page.locator('input[name="picture"]').setInputFiles(filePath);
    await page.getByRole('button', { name: 'Submit' }).click();

    await expect(page.getByText('E2E User')).toBeVisible({ timeout: 10_000 });
    await expect(page.getByText('avatar.png')).toBeVisible();
    await expect(page.locator('img[src^="data:image"]')).toBeVisible();
  });
});
