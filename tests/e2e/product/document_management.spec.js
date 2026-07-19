// @ts-check
import { readFileSync } from 'node:fs';
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';

const sampleFile = readFileSync('test/fixtures/files/sample.txt');

test('category filters carry an empty category into document upload', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-category-prescriptions').click();

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents\?category=prescriptions$/);
  await expect(page.getByTestId('documents-category-filter-prescriptions')).toHaveAttribute('aria-current', 'page');
  await expect(page.getByRole('heading', { name: 'No prescription documents yet' })).toBeVisible();

  await page.getByTestId('documents-category-filter-all').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByRole('link', { name: /Advance Directive/ })).toBeVisible();

  await page.getByTestId('documents-category-filter-prescriptions').click();
  await expect(page.getByRole('heading', { name: 'No prescription documents yet' })).toBeVisible();
  await page.getByTestId('documents-empty-add-link').click();

  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await expect(page.getByTestId('document-category-field')).toHaveValue('prescriptions');
});

test('filename search stays on the document index and composes with category filters', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();

  await page.getByTestId('documents-search-field').fill('ADVANCE-DIRECTIVE');
  await page.getByTestId('documents-search-field').press('Enter');

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents\?q=ADVANCE-DIRECTIVE$/);
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await expect(page.getByTestId('documents-search-field')).toHaveValue('ADVANCE-DIRECTIVE');
  await expect(page.getByRole('link', { name: /Advance Directive/ })).toBeVisible();

  await page.getByTestId('documents-category-filter-insurance').click();
  await expect(page.getByTestId('documents-category-filter-insurance')).toHaveAttribute('aria-current', 'page');
  await expect(page.getByRole('heading', { name: 'No documents found' })).toBeVisible();
  await expect(page.getByText(/No file names match “ADVANCE-DIRECTIVE” in insurance/)).toBeVisible();

  await page.getByTestId('documents-search-field').evaluate((input) => {
    input.value = '';
    input.dispatchEvent(new Event('search', { bubbles: true }));
  });

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents\?category=insurance$/);
  await expect(page.getByRole('heading', { name: 'No insurance documents yet' })).toBeVisible();
});

test('admin can upload multiple documents at once', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await page.getByTestId('document-description-field').fill('Uploaded together by the QA browser harness.');
  await page.getByTestId('document-category-field').selectOption('medical');
  await page.getByTestId('document-file-field').setInputFiles([
    { name: 'browser-multi-one.txt', mimeType: 'text/plain', buffer: sampleFile },
    { name: 'browser-multi-two.txt', mimeType: 'text/plain', buffer: sampleFile },
  ]);
  await expect(page.getByTestId('document-file-summary')).toContainText('2 files selected');
  await expect(page.getByTestId('document-file-list')).toContainText('browser-multi-one.txt');
  await expect(page.getByTestId('document-file-list')).toContainText('browser-multi-two.txt');
  await expect(page.getByTestId('document-file-category-0')).toHaveValue('medical');
  await expect(page.getByTestId('document-file-category-1')).toHaveValue('medical');
  await page.getByTestId('document-file-category-1').selectOption('therapy');
  await page.getByTestId('document-upload-submit').click();

  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await expect(page.getByTestId('flash-notice')).toContainText('2 documents uploaded and being prepared.');
  await expect(page.getByRole('link', { name: /browser-multi-one/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /browser-multi-two/ })).toBeVisible();
});

test('document details link to the original file without showing extracted text', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByRole('link', { name: /Advance Directive/ }).click();

  await expect(page.getByText('View document text')).toHaveCount(0);
  const downloadOriginal = page.getByTestId('document-download-original');
  await expect(downloadOriginal).toHaveAttribute('download', 'advance-directive.txt');
  await expect(downloadOriginal).toHaveAttribute('href', /\/documents\/\d+\/original$/);
});

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
