// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';

test('upload form keeps required file validation in the browser', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await page.getByTestId('document-upload-submit').click();

  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await expect(page.getByTestId('document-file-field')).toBeVisible();
  expect(await page.getByTestId('document-file-field').evaluate((input) => input.validity.valueMissing)).toBe(true);
});

test('an unsupported file is rejected after choosing from all file types', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  const fileField = page.getByTestId('document-file-field');
  expect(await fileField.getAttribute('accept')).toBeNull();
  await fileField.setInputFiles({
    name: 'browser-unsupported.svg',
    mimeType: 'image/svg+xml',
    buffer: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
  });
  await page.getByTestId('document-upload-submit').click();

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents\/new$/);
  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await expect(page.getByTestId('document-form-errors')).toContainText('unsupported image type');
  await expect(page.getByTestId('document-file-summary')).toContainText('No files selected');
  await expect(page.getByTestId('document-category-field')).toHaveCount(0);
  await expect(page.getByTestId('document-description-field')).toHaveCount(0);
});

test('partially successful uploads return to Documents with both success and failure feedback', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();
  await page.getByTestId('document-file-field').setInputFiles([
    { name: 'browser-partial-supported.txt', mimeType: 'text/plain', buffer: Buffer.from('A supported document.') },
    { name: 'browser-partial-unsupported.svg', mimeType: 'image/svg+xml', buffer: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"></svg>') },
  ]);
  await page.getByTestId('document-upload-submit').click();

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await expect(page.getByTestId('flash-notice')).toContainText('1 document uploaded and being prepared.');
  await expect(page.getByTestId('flash-alert')).toContainText('1 file could not be uploaded: browser-partial-unsupported.svg.');
  await expect(page.getByRole('link', { name: /browser-partial-supported/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /browser-partial-unsupported/ })).toHaveCount(0);
});

test('editing document with blank title shows a validation error', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await page.getByRole('link', { name: /Advance Directive|QA Planning Document/ }).first().click();
  await page.getByTestId('document-edit-link').click();

  await page.getByTestId('document-title-field').fill('');
  await page.getByTestId('document-save-submit').click();

  await expect(page.getByRole('heading', { name: 'Edit Document' })).toBeVisible();
  await expect(page.getByTestId('document-form-errors')).toContainText("Title can't be blank");
});
