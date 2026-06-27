// @ts-check
import { test, expect } from '@playwright/test';
import { openDependentWorkspace } from '../helpers/auth';

test('ai assistant loads without submitting a query', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByRole('link', { name: 'Open Assistant' }).click();

  await expect(page.getByRole('heading', { name: 'AI Assistant' })).toBeVisible();
  await expect(page.getByText('Suggested questions')).toBeVisible();
  await expect(page.getByText('No guessing')).toBeVisible();
  await expect(page.getByPlaceholder('Ask a question about documents, care progress, or next steps...')).toBeVisible();
});
