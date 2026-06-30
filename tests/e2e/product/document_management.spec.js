// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';

test('admin can edit document metadata', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByRole('link', { name: /Advance Directive/ }).click();
  await page.getByTestId('document-edit-link').click();

  await expect(page.getByRole('heading', { name: 'Edit Document' })).toBeVisible();
  await page.getByTestId('document-title-field').fill('QA Planning Document');
  await page.getByTestId('document-description-field').fill('Updated by the QA browser harness.');
  await page.getByTestId('document-category-field').selectOption('medical');
  await page.getByTestId('document-save-submit').click();

  await expect(page.getByTestId('flash-notice')).toContainText('Document updated');
  await expect(page.getByRole('heading', { name: 'QA Planning Document' })).toBeVisible();
  await expect(page.getByText('Updated by the QA browser harness.')).toBeVisible();
});
