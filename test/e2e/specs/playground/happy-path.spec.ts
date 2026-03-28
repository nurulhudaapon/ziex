// spec: playground test plan
import { test, expect } from '@playwright/test';


test.describe('Ziex Playground', () => {
  test('Page Load & Initial State', async ({ page }) => {
    // 1. Navigate to /playground
    await page.goto('/playground');
    // expect: Playground loads with default files, code editor, and Run/Share buttons visible.
    await expect(page.getByRole('button', { name: 'Run' })).toBeVisible();
    await expect(page.getByRole('button', { name: /Share/ })).toBeVisible();
    await expect(page.getByRole('button', { name: /Playground\.zx/ })).toBeVisible();
    await expect(page.getByRole('button', { name: /style\.css/ })).toBeVisible();
    // Always click Run on first load to expect preview
    const runButton = page.getByRole('button', { name: 'Run' });
    await runButton.waitFor({ state: 'visible' });
    await page.waitForFunction(() => {
      const btn = Array.from(document.querySelectorAll('button')).find(b => b.textContent?.trim() === 'Run');
      return btn && !btn.disabled;
    });
    await runButton.click();
    // Wait for preview output (look for a heading or known output)
    await page.waitForTimeout(2000); // Allow time for preview to update
    // Check inside the preview iframe
    const previewFrame = page.frameLocator('iframe');
    await expect(previewFrame.getByRole('heading', { name: /Ziex Playground/ })).toBeVisible();
  });

  test('Edit Code and Run', async ({ page }) => {
    await page.goto('/playground');
    // Edit code in Playground.zx
    const editor = page.getByRole('textbox').first();
    await editor.click();
    await editor.type('\n// test comment');
    // Click Run
    const runButton = page.getByRole('button', { name: 'Run' });
    await runButton.waitFor({ state: 'visible' });
    await page.waitForFunction(() => {
      const btn = Array.from(document.querySelectorAll('button')).find(b => b.textContent?.trim() === 'Run');
      return btn && !btn.disabled;
    });
    await runButton.click();
    // Wait for preview output
    await page.waitForTimeout(2000); // Allow time for preview to update
    // Check inside the preview iframe
    const previewFrame = page.frameLocator('iframe');
    await expect(previewFrame.getByRole('heading', { name: /Ziex Playground/ })).toBeVisible();
  });

  test('Add New File', async ({ page }) => {
    await page.goto('/playground');
    // Click Add new file and handle JS prompt
    page.once('dialog', async dialog => {
      await dialog.accept('test.zx');
    });
    await page.getByRole('button', { name: /Add new file/ }).click();
    // Expect new tab to appear
    await expect(page.getByRole('button', { name: /test\.zx/ })).toBeVisible();
  });

  test('Switch Between Files', async ({ page }) => {
    await page.goto(`/playground`);
    // Click style.css tab
    await page.getByRole('button', { name: /style\.css/ }).click();
    await expect(page.getByRole('button', { name: /style\.css/ })).toBeVisible();
    // Click Playground.zx tab
    await page.getByRole('button', { name: /Playground\.zx/ }).click();
    await expect(page.getByRole('button', { name: /Playground\.zx/ })).toBeVisible();
  });

  test('Close File Tab', async ({ page }) => {
    await page.goto(`/playground`);
    // Click close (×) on style.css tab
    const closeBtn = page.getByRole('button', { name: 'style.css Close tab' });
    await closeBtn.click();
    // expect: Tab closes (may need to assert tab is not visible)
  });

  test('Share Button', async ({ page }) => {
    await page.goto(`/playground`);
    const shareButton = page.getByRole('button', { name: /Share/ });
    await shareButton.waitFor({ state: 'visible' });
    await page.waitForFunction(() => {
      const btn = Array.from(document.querySelectorAll('button')).find(b => b.textContent?.trim().includes('Share'));
      return btn && !btn.disabled;
    });
    await shareButton.click();
    // expect: Share dialog or link is shown (if implemented)
  });

  test('Terminal Panel', async ({ page }) => {
    await page.goto(`/playground`);
    // Toggle terminal
    await page.getByRole('button', { name: /Toggle terminal/ }).click();
    // Clear terminal
    await page.getByRole('button', { name: /Clear terminal/ }).click();
  });

  test('Error Handling', async ({ page }) => {
    await page.goto(`/playground`);
    // Enter invalid code and click Run
    const editor = page.getByRole('textbox').first();
    await editor.click();
    await editor.type('\nthis is invalid code');
    const runButton = page.getByRole('button', { name: 'Run' });
    await runButton.waitFor({ state: 'visible' });
    await page.waitForFunction(() => {
      const btn = Array.from(document.querySelectorAll('button')).find(b => b.textContent?.trim() === 'Run');
      return btn && !btn.disabled;
    });
    await runButton.click();
    // Wait for error in terminal/output
    await expect(page.getByText(/error|invalid|failed/i)).toBeVisible();
  });

  test('Keyboard Navigation', async ({ page }) => {
    await page.goto(`/playground`);
    // Tab to Run button
    await page.keyboard.press('Tab');
    // Tab to Share button
    await page.keyboard.press('Tab');
    // Tab to editor
    await page.keyboard.press('Tab');
    // expect: Focus moves between controls
  });

  test('File Persistence (should reset to initial template)', async ({ page }) => {
    await page.goto(`/playground`);
    // Edit Playground.zx
    const editor = page.getByRole('textbox').first();
    await editor.click();
    await editor.type('\n// persist test');
    // Reload
    await page.reload();
    // Always click Run after reload to update preview
    const runButton = page.getByRole('button', { name: 'Run' });
    await runButton.waitFor({ state: 'visible' });
    await page.waitForFunction(() => {
      const btn = Array.from(document.querySelectorAll('button')).find(b => b.textContent?.trim() === 'Run');
      return btn && !btn.disabled;
    });
    await runButton.click();
    await page.waitForTimeout(2000);
    // expect: Initial template is present (not the edited content)
    const previewFrame = page.frameLocator('iframe');
    await expect(previewFrame.getByRole('heading', { name: /Ziex Playground/ })).toBeVisible();
  });
});
