// @ts-check
import { readFileSync } from 'node:fs';
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';

const sampleFile = readFileSync('test/fixtures/files/sample.txt');

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
  await expect(page.getByTestId('flash-notice')).toContainText('2 documents uploaded and queued for evaluation.');
  await expect(page.getByRole('link', { name: /browser-multi-one/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /browser-multi-two/ })).toBeVisible();
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
