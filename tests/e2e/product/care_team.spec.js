// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';

test('care team page shows invited active member and permissions', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();

  await expect(page.getByRole('heading', { name: 'Care Team' })).toBeVisible();
  await expect(page.getByTestId('care-team-invite-link')).toBeVisible();
  await expect(page.getByText('Therapist User')).toBeVisible();
  await expect(page.getByText('therapist@example.test')).toBeVisible();
  await expect(page.getByText('Therapy')).toBeVisible();
  await expect(page.getByText('Medical')).toBeVisible();
  await expectAccessible(page);
});

test('admin can invite a care team member with category permissions', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();
  await page.getByTestId('care-team-invite-link').click();

  await expect(page.getByRole('heading', { name: 'Invite Care Team Member' })).toBeVisible();
  await page.getByTestId('care-team-name-field').fill('QA Advocate');
  await page.getByTestId('care-team-email-field').fill('qa-advocate@example.test');
  await page.getByTestId('care-team-role-field').selectOption('advocate');
  await page.getByTestId('care-team-permission-educational').check();
  await page.getByTestId('care-team-permission-general').check();
  await page.getByTestId('care-team-submit').click();

  await expect(page.getByTestId('flash-notice')).toContainText('Care team member invited');
  await expect(page.getByText('QA Advocate')).toBeVisible();
  await expect(page.getByText('qa-advocate@example.test')).toBeVisible();
});
