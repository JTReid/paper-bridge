// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';

test('care team page shows saved contact details', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();

  await expect(page.getByRole('heading', { name: 'Care Team' })).toBeVisible();
  await expect(page.getByTestId('care-team-add-link')).toBeVisible();
  await expect(page.getByText('Therapist User')).toBeVisible();
  await expect(page.getByText('therapist@example.test')).toBeVisible();
  await expect(page.getByText('850-555-0100')).toBeVisible();
  await expect(page.getByText('Therapist', { exact: true })).toBeVisible();
  await expect(page.getByText(/Invitation pending|Can access|Access removed/)).toHaveCount(0);
  await expectAccessible(page);
});

test('admin can add and edit a care team contact and recall their email for sharing', async ({ page }) => {
  const contactEmail = `qa-advocate-${Date.now()}@example.test`;
  const updatedEmail = `updated-${contactEmail}`;

  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();
  await expect(page.getByRole('heading', { name: 'Care Team', level: 1 })).toBeVisible();
  await page.getByTestId('care-team-add-link').click();

  await expect(page.getByRole('heading', { name: 'Add Care Team Member' })).toBeVisible();
  await expect(page.getByTestId('care-team-status-field')).toHaveCount(0);
  await expect(page.getByRole('checkbox')).toHaveCount(0);
  await page.getByTestId('care-team-name-field').fill('QA Advocate');
  await page.getByTestId('care-team-email-field').fill(contactEmail);
  await page.getByTestId('care-team-role-field').selectOption('advocate');
  await page.getByTestId('care-team-phone-field').fill('(850) 555-0123 ext. 4');
  await page.getByRole('button', { name: 'Add Member', exact: true }).click();

  await expect(page.getByTestId('flash-notice')).toContainText('Care team member added.');
  const card = page.locator('[data-testid^="care-team-member-"]').filter({ hasText: contactEmail });
  await expect(card).toContainText('QA Advocate');
  await expect(card).toContainText('(850) 555-0123 ext. 4');
  await card.getByRole('link', { name: 'Edit' }).click();

  await expect(page.getByTestId('care-team-phone-field')).toHaveValue('(850) 555-0123 ext. 4');
  await page.getByTestId('care-team-name-field').fill('QA Therapist');
  await page.getByTestId('care-team-role-field').selectOption('therapist');
  await page.getByTestId('care-team-email-field').fill(updatedEmail);
  await page.getByTestId('care-team-phone-field').fill('850-555-0199');
  await page.getByRole('button', { name: 'Save Changes' }).click();

  const updatedCard = page.locator('[data-testid^="care-team-member-"]').filter({ hasText: updatedEmail });
  await expect(updatedCard).toContainText('QA Therapist');
  await expect(updatedCard).toContainText('850-555-0199');
  await page.getByRole('link', { name: 'Documents', exact: true }).click();
  await page.locator('[data-testid^="document-share-button-"]').first().click();
  await page.getByTestId('document-share-recipient-select').selectOption({ label: `QA Therapist (${updatedEmail})` });
  await expect(page.getByTestId('document-share-recipient-email')).toHaveValue(updatedEmail);
  await expect(page.getByTestId('document-share-recipient-select').locator(`option[value="${contactEmail}"]`)).toHaveCount(0);

  await page.getByTestId('document-share-close').click();
  await page.getByRole('link', { name: 'Care Team', exact: true }).click();
  await updatedCard.getByRole('button', { name: 'Remove' }).click();
  await expect(updatedCard).toHaveCount(0);
});
