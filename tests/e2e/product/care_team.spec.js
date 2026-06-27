// @ts-check
import { test, expect } from '@playwright/test';
import { openDependentWorkspace } from '../helpers/auth';

test('care team page shows invited active member and permissions', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByRole('link', { name: 'Care Team' }).last().click();

  await expect(page.getByRole('heading', { name: 'Care Team' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Invite Member' })).toBeVisible();
  await expect(page.getByText('Therapist User')).toBeVisible();
  await expect(page.getByText('therapist@example.test')).toBeVisible();
  await expect(page.getByText('Therapy')).toBeVisible();
  await expect(page.getByText('Medical')).toBeVisible();
});
