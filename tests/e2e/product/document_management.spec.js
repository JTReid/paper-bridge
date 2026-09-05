// @ts-check
import { readFileSync } from 'node:fs';
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';
import { completeDocumentInitialMetadata } from '../helpers/backend';
import { expectAccessible } from '../helpers/accessibility';

const sampleFile = readFileSync('test/fixtures/files/sample.txt');

test('category filters lead to a file-only upload form with an unfiltered picker', async ({ page }) => {
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
  await expect(page.getByTestId('document-category-field')).toHaveCount(0);
  await expect(page.getByTestId('document-description-field')).toHaveCount(0);
  expect(await page.getByTestId('document-file-field').getAttribute('accept')).toBeNull();
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
  await page.getByTestId('document-file-field').setInputFiles([
    { name: 'browser-multi-one.txt', mimeType: 'text/plain', buffer: Buffer.concat([sampleFile, Buffer.from('\nFirst browser batch document.')]) },
    { name: 'browser-multi-two.txt', mimeType: 'text/plain', buffer: Buffer.concat([sampleFile, Buffer.from('\nSecond browser batch document.')]) },
  ]);
  await expect(page.getByTestId('document-file-summary')).toContainText('2 files selected');
  await expect(page.getByTestId('document-file-list')).toContainText('browser-multi-one.txt');
  await expect(page.getByTestId('document-file-list')).toContainText('browser-multi-two.txt');
  await expect(page.getByTestId('document-file-list').getByRole('combobox')).toHaveCount(0);
  await page.getByTestId('document-upload-submit').click();

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await expect(page.getByTestId('flash-notice')).toContainText('2 documents uploaded and being prepared.');
  await expect(page.getByRole('link', { name: /browser-multi-one/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /browser-multi-two/ })).toBeVisible();
});

test('removing and clearing pending files changes the submitted selection', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  const fileField = page.getByTestId('document-file-field');
  const files = [
    { name: 'browser-remove-before-upload.txt', mimeType: 'text/plain', buffer: sampleFile },
    { name: 'browser-keep-selected.txt', mimeType: 'text/plain', buffer: sampleFile },
  ];
  await fileField.setInputFiles(files);
  await expect(page.getByTestId('document-selected-file')).toHaveCount(2);
  await expectAccessible(page);

  await page.getByTestId('document-file-clear-selection').click();
  await expect(page.getByTestId('document-file-summary')).toContainText('No files selected');
  await expect(page.getByTestId('document-selected-file')).toHaveCount(0);
  expect(await selectedFileNames(fileField)).toEqual([]);
  expect(await fileField.evaluate((input) => input.validity.valueMissing)).toBe(true);

  // Dropped files must use the same editable selection as the native picker.
  const droppedFiles = await page.evaluateHandle((fileNames) => {
    const transfer = new DataTransfer();
    for (const name of fileNames) {
      transfer.items.add(new File([`A browser upload selection test for ${name}.`], name, { type: 'text/plain' }));
    }
    return transfer;
  }, files.map((file) => file.name));
  await page.locator('[data-file-dropzone-target="dropzone"]').dispatchEvent('drop', { dataTransfer: droppedFiles });
  await droppedFiles.dispose();
  await expect(page.getByTestId('document-file-summary')).toContainText('2 files selected');
  await page.getByRole('button', { name: 'Remove browser-remove-before-upload.txt', exact: true }).click();

  await expect(page.getByTestId('document-selected-file')).toHaveCount(1);
  await expect(page.getByTestId('document-file-summary')).toContainText('1 file selected');
  expect(await selectedFileNames(fileField)).toEqual(['browser-keep-selected.txt']);
  await page.getByTestId('document-upload-submit').click();

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByTestId('flash-notice')).toContainText('1 document uploaded and being prepared.');
  await expect(page.getByRole('link', { name: /browser-keep-selected/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /browser-remove-before-upload/ })).toHaveCount(0);
});

test('initial processing unlocks metadata editing and never replaces later corrections', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();
  await page.getByTestId('document-file-field').setInputFiles({
    name: 'browser-initial-metadata.txt',
    mimeType: 'text/plain',
    buffer: Buffer.concat([sampleFile, Buffer.from('\nInitial metadata browser document.')]),
  });
  await page.getByTestId('document-upload-submit').click();

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByTestId('flash-notice')).toContainText('1 document uploaded and being prepared.');
  await page.getByRole('link', { name: /browser-initial-metadata/ }).click();
  await expect(page).toHaveURL(/\/documents\/\d+$/);
  const documentId = page.url().match(/\/documents\/(\d+)$/)?.[1];
  expect(documentId).toBeTruthy();
  await page.getByTestId('document-edit-link').click();

  await expect(page.getByTestId('document-metadata-pending')).toBeVisible();
  await expect(page.getByTestId('document-title-field')).toBeEnabled();
  await expect(page.getByTestId('document-category-field')).toBeDisabled();
  await expect(page.getByTestId('document-description-field')).toBeDisabled();
  await expectAccessible(page);
  await expect(page.locator('turbo-cable-stream-source')).toHaveAttribute('connected', '');
  await page.getByTestId('document-title-field').fill('My unfinished title correction');

  // The process-local test Cable adapter cannot deliver between the runner and Puma.
  // Apply the actual completion broadcasts to prove the in-place update without a live model.
  const metadataStreams = completeDocumentInitialMetadata(documentId, {
    category: 'medical',
    description: 'Automatically generated description of the uploaded record.',
  });
  expect(metadataStreams.some((stream) => stream.includes(`editable_metadata_document_${documentId}`))).toBe(true);
  await page.evaluate((streams) => {
    for (const stream of streams) window.Turbo.renderStreamMessage(stream);
  }, metadataStreams);
  await expect(page.getByTestId('document-metadata-pending')).toHaveCount(0);
  await expect(page.getByTestId('document-title-field')).toHaveValue('My unfinished title correction');
  await expect(page.getByTestId('document-category-field')).toBeEnabled();
  await expect(page.getByTestId('document-category-field')).toHaveValue('medical');
  await expect(page.getByTestId('document-description-field')).toBeEnabled();
  await expect(page.getByTestId('document-description-field')).toHaveValue('Automatically generated description of the uploaded record.');

  await page.getByTestId('document-category-field').selectOption('therapy');
  await page.getByTestId('document-description-field').fill('My corrected description of the therapy record.');
  await page.getByTestId('document-save-submit').click();
  await expect(page.getByTestId('flash-notice')).toContainText('Document updated');

  const retryStreams = completeDocumentInitialMetadata(documentId, {
    category: 'general',
    description: 'A later processing retry must not apply this description.',
  });
  expect(retryStreams).toEqual([]);
  await page.getByTestId('document-edit-link').click();
  await expect(page.getByTestId('document-category-field')).toHaveValue('therapy');
  await expect(page.getByTestId('document-description-field')).toHaveValue('My corrected description of the therapy record.');
});

test('Word and ZIP uploads remain downloadable and immediately editable without AI processing', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  const files = [
    {
      name: 'browser-storage-only.docx',
      mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      buffer: Buffer.from('PK\x03\x04Synthetic Word original kept without parsing.'),
    },
    {
      name: 'browser-storage-only.zip',
      mimeType: 'application/zip',
      buffer: Buffer.from('UEsFBgAAAAAAAAAAAAAAAAAAAAAAAA==', 'base64'),
    },
  ];
  await page.getByTestId('document-file-field').setInputFiles(files);
  await page.getByTestId('document-upload-submit').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);

  for (const file of files) {
    const row = page.locator('[data-testid^="document-row-"]').filter({ hasText: file.name });
    await expect(row).toContainText('Stored—not processed');
    await row.getByRole('link').first().click();
    await expect(page).toHaveURL(/\/documents\/\d+$/);
    await expect(page.getByTestId('document-processing-status')).toContainText('Stored—not processed');
    await expect(page.getByTestId('document-storage-only-notice')).toBeVisible();
    await expect(page.getByTestId('document-processing-stat-summary')).toContainText('Not supported');
    await expect(page.getByTestId('document-processing-stat-ask-paperbridge')).toContainText('Not supported');
    await expect(page.getByText('Your summary will appear when it’s ready.')).toHaveCount(0);

    const original = page.getByTestId('document-download-original');
    await expect(original).toHaveAttribute('download', file.name);
    const originalPath = await original.getAttribute('href');
    expect(originalPath).toMatch(/\/documents\/\d+\/original$/);
    const response = await page.request.get(originalPath);
    expect(response.ok()).toBe(true);
    expect(await response.body()).toEqual(file.buffer);

    await page.getByTestId('document-edit-link').click();
    await expect(page.getByTestId('document-metadata-pending')).toHaveCount(0);
    await expect(page.getByTestId('document-category-field')).toBeEnabled();
    await expect(page.getByTestId('document-category-field')).toHaveValue('general');
    await expect(page.getByTestId('document-description-field')).toBeEnabled();
    await expect(page.getByTestId('document-description-field')).toHaveValue('');
    await page.getByTestId('document-category-field').selectOption('insurance');
    await page.getByTestId('document-description-field').fill(`My saved original: ${file.name}`);
    await page.getByTestId('document-save-submit').click();
    await expect(page.getByTestId('flash-notice')).toContainText('Document updated');
    await expect(page.getByText(`My saved original: ${file.name}`)).toBeVisible();
    await expect(page.getByTestId('document-processing-status')).toContainText('Stored—not processed');
    await page.getByTestId('document-back-to-documents').click();
    await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  }
});

test('a selection over 50 files can be reduced to the supported batch size and uploaded', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  const files = Array.from({ length: 51 }, (_, index) => ({
    name: `browser-limit-recovery-${String(index + 1).padStart(2, '0')}.txt`,
    mimeType: 'text/plain',
    buffer: Buffer.from(`Distinct browser batch limit recovery document ${index + 1}.`),
  }));
  const fileField = page.getByTestId('document-file-field');
  await fileField.setInputFiles(files);
  await expect(page.getByTestId('document-file-summary')).toContainText('51 files selected');
  await expect(page.getByTestId('document-file-limit-error')).toContainText('Upload up to 50 files at a time');
  await expect(fileField).toHaveAttribute('aria-invalid', 'true');
  expect(await fileField.evaluate((input) => input.validity.customError)).toBe(true);
  await page.getByTestId('document-upload-submit').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/documents\/new$/);
  await expect(page.getByTestId('document-selected-file')).toHaveCount(51);

  await page.getByTestId('document-file-remove-50').click();
  await expect(page.getByTestId('document-file-summary')).toContainText('50 files selected');
  await expect(page.getByTestId('document-file-limit-error')).toBeHidden();
  expect(await fileField.evaluate((input) => input.validity.valid)).toBe(true);
  await page.getByTestId('document-upload-submit').click();

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByTestId('flash-notice')).toContainText('50 documents uploaded');
  await expect(page.locator('[data-testid^="document-row-"]').filter({ hasText: 'browser-limit-recovery-' })).toHaveCount(50);
  await expect(page.getByRole('link', { name: /browser-limit-recovery-51/ })).toHaveCount(0);
});

test('document details link to the original file without showing extracted text', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await page.getByRole('link', { name: /Advance Directive/ }).click();

  await expect(page.getByText('View document text')).toHaveCount(0);
  const downloadOriginal = page.getByTestId('document-download-original');
  await expect(downloadOriginal).toBeVisible();
  await expect(downloadOriginal).toHaveAttribute('download', 'advance-directive.txt');
  await expect(downloadOriginal).toHaveAttribute('href', /\/documents\/\d+\/original$/);
  await expect(page.getByTestId('document-processing-status').getByTestId('document-download-original')).toHaveCount(0);
  await expect(downloadOriginal.locator('..').getByTestId('document-edit-link')).toBeVisible();
});

test('admin can edit document metadata', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await page.getByRole('link', { name: /Advance Directive/ }).click();
  await expect(page).toHaveURL(/\/documents\/\d+$/);
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

async function selectedFileNames(fileField) {
  return fileField.evaluate((input) => Array.from(input.files).map((file) => file.name));
}
