// @ts-check
import { test, expect } from '@playwright/test';
import { openDependentWorkspace } from '../helpers/auth';

test('document share modal opens and selects a care team recipient', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByRole('link', { name: 'View all' }).click();

  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await page.getByRole('button', { name: 'Share Advance Directive' }).click();

  const dialog = page.getByRole('dialog', { name: 'Share Documents' });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByText('send the original files by email')).toBeVisible();

  await page.locator('select[name="care_team_recipient"]').selectOption('therapist@example.test');
  await expect(page.getByPlaceholder('Recipient email')).toHaveValue('therapist@example.test');
  await expect(dialog.getByRole('button', { name: 'Share Selected' })).toBeVisible();
});
