// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';

test('document share modal opens and selects a care team recipient', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();

  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await page.locator('[data-testid^="document-share-button-"]').first().click();

  const dialog = page.getByRole('dialog', { name: 'Share Documents' });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByText('send the original files by email')).toBeVisible();
  await expectAccessible(page);

  await page.getByTestId('document-share-recipient-select').selectOption('therapist@example.test');
  await expect(page.getByTestId('document-share-recipient-email')).toHaveValue('therapist@example.test');
  await page.getByTestId('document-share-subject').fill('QA share smoke');
  await page.getByTestId('document-share-message').fill('Sent from the QA browser harness.');
  await page.getByTestId('document-share-submit').click();

  await expect(page.getByTestId('flash-notice')).toContainText('Documents shared with therapist@example.test');
});
