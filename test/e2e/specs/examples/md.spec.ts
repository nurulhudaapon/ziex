import { test, expect } from '@playwright/test';

test.describe('Markdown (MDZX) Example', () => {
  test('renders markdown headings and embedded zig example', async ({ page }) => {
    await page.goto('/examples/md');

    await expect(page.getByRole('heading', { name: 'H1 Header', exact: true })).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByRole('heading', { name: 'H2 Header', exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: '1. Headers & Formatting' })).toBeVisible();
    await expect(page.getByText('How does that work?')).toBeVisible();
    await expect(page.getByText(/Hello,\s*ZX\s*Dev!/i)).toBeVisible();
  });
});
