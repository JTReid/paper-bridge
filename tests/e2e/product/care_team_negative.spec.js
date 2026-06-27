// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';

test('care team invite with blank email shows validation errors', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();
  await page.getByTestId('care-team-invite-link').click();

  await page.getByTestId('care-team-name-field').fill('Missing Email Invite');
  await page.getByTestId('care-team-submit').click();

  await expect(page.getByRole('heading', { name: 'Invite Care Team Member' })).toBeVisible();
  await expect(page.getByTestId('care-team-form-errors')).toContainText(/Email|can't be blank|invalid/i);
});

test('care team invite with malformed email is blocked by browser validation', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();
  await page.getByTestId('care-team-invite-link').click();

  await page.getByTestId('care-team-name-field').fill('Malformed Email Invite');
  await page.getByTestId('care-team-email-field').fill('not-an-email');
  await page.getByTestId('care-team-submit').click();

  await expect(page.getByRole('heading', { name: 'Invite Care Team Member' })).toBeVisible();
  expect(await page.getByTestId('care-team-email-field').evaluate((input) => input.validity.typeMismatch)).toBe(true);
});

test('duplicate care team invite shows validation errors', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();
  await page.getByTestId('care-team-invite-link').click();

  await page.getByTestId('care-team-name-field').fill('Duplicate Therapist');
  await page.getByTestId('care-team-email-field').fill('therapist@example.test');
  await page.getByTestId('care-team-submit').click();

  await expect(page.getByRole('heading', { name: 'Invite Care Team Member' })).toBeVisible();
  await expect(page.getByTestId('care-team-form-errors')).toContainText(/already|taken|exists/i);
});
