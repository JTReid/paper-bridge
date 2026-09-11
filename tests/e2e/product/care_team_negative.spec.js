// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';

test('care team contact with blank email shows validation errors', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();
  await page.getByTestId('care-team-add-link').click();

  await page.getByTestId('care-team-name-field').fill('Missing Email Contact');
  await page.getByTestId('care-team-submit').click();

  await expect(page.getByRole('heading', { name: 'Add Care Team Member' })).toBeVisible();
  await expect(page.getByTestId('care-team-form-errors')).toContainText(/Email|can't be blank|invalid/i);
});

test('care team contact with malformed email is blocked by browser validation', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();
  await page.getByTestId('care-team-add-link').click();

  await page.getByTestId('care-team-name-field').fill('Malformed Email Contact');
  await page.getByTestId('care-team-email-field').fill('not-an-email');
  await page.getByTestId('care-team-submit').click();

  await expect(page.getByRole('heading', { name: 'Add Care Team Member' })).toBeVisible();
  expect(await page.getByTestId('care-team-email-field').evaluate((input) => input.validity.typeMismatch)).toBe(true);
});

test('duplicate care team contact shows validation errors', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();
  await page.getByTestId('care-team-add-link').click();

  await page.getByTestId('care-team-name-field').fill('Duplicate Therapist');
  await page.getByTestId('care-team-email-field').fill('therapist@example.test');
  await page.getByTestId('care-team-submit').click();

  await expect(page.getByRole('heading', { name: 'Add Care Team Member' })).toBeVisible();
  await expect(page.getByTestId('care-team-form-errors')).toContainText(/already|taken|exists/i);
});
