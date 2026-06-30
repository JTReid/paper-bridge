// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';

test('upload form keeps required file validation in the browser', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await page.getByTestId('document-title-field').fill('QA Missing File');
  await page.getByTestId('document-upload-submit').click();

  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await expect(page.getByTestId('document-file-field')).toBeVisible();
  expect(await page.getByTestId('document-file-field').evaluate((input) => input.validity.valueMissing)).toBe(true);
});

test('editing document with blank title shows a validation error', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByRole('link', { name: /Advance Directive|QA Planning Document/ }).first().click();
  await page.getByTestId('document-edit-link').click();

  await page.getByTestId('document-title-field').fill('');
  await page.getByTestId('document-save-submit').click();

  await expect(page.getByRole('heading', { name: 'Edit Document' })).toBeVisible();
  await expect(page.getByTestId('document-form-errors')).toContainText("Title can't be blank");
});
