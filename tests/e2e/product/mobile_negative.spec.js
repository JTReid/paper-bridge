// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';

test.describe('mobile negative workflows', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('mobile document share blocks blank recipient', async ({ page }) => {
    await openDependentWorkspace(page);
    await page.getByTestId('dependent-documents-link').click();
    await page.locator('[data-testid^="document-share-button-"]').first().click();

    await page.getByTestId('document-share-submit').click();

    await expect(page.getByRole('dialog', { name: 'Share Documents' })).toBeVisible();
    expect(await page.getByTestId('document-share-recipient-email').evaluate((input) => input.validity.valueMissing)).toBe(true);
  });

  test('mobile care team invite shows blank email validation', async ({ page }) => {
    await openDependentWorkspace(page);
    await page.getByTestId('dependent-care-team-link').click();
    await page.getByTestId('care-team-invite-link').click();

    await page.getByTestId('care-team-name-field').fill('Mobile Missing Email');
    await page.getByTestId('care-team-submit').click();

    await expect(page.getByRole('heading', { name: 'Invite Care Team Member' })).toBeVisible();
    await expect(page.getByTestId('care-team-form-errors')).toContainText(/Email|can't be blank|invalid/i);
  });
});
