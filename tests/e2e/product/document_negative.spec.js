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

test('a corrupt supported image is still rejected after choosing from all file types', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  const fileField = page.getByTestId('document-file-field');
  expect(await fileField.getAttribute('accept')).toBeNull();
  await fileField.setInputFiles({
    name: 'browser-invalid.png',
    mimeType: 'image/png',
    buffer: Buffer.from('This is not a valid PNG image.'),
  });
  await page.getByTestId('document-upload-submit').click();

  await expect(page).toHaveURL(/\/profiles\/\d+\/documents\/new$/);
  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await expect(page.getByTestId('document-form-errors')).toContainText('does not contain a valid image');
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
    { name: 'browser-partial-invalid.png', mimeType: 'image/png', buffer: Buffer.from('A corrupt supported image.') },
  ]);
  await page.getByTestId('document-upload-submit').click();

  await expect(page).toHaveURL(/\/profiles\/\d+\/documents$/);
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await expect(page.getByTestId('flash-notice')).toContainText('1 document uploaded and being prepared.');
  await expect(page.getByTestId('flash-alert')).toContainText('1 file could not be uploaded');
  await expect(page.getByTestId('flash-alert')).toContainText('browser-partial-invalid.png');
  await expect(page.getByTestId('flash-alert')).toContainText('does not contain a valid image');
  await expect(page.getByRole('link', { name: /browser-partial-supported/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /browser-partial-invalid/ })).toHaveCount(0);
});

test('the server rejects all 51 files when browser batch validation is bypassed', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();
  await page.getByTestId('document-file-field').setInputFiles(
    Array.from({ length: 51 }, (_, index) => ({
      name: `browser-server-limit-${index + 1}.txt`,
      mimeType: 'text/plain',
      buffer: Buffer.from(`Distinct server-side batch limit document ${index + 1}.`),
    })),
  );

  const rejectedUpload = page.waitForResponse((response) =>
    response.request().method() === 'POST' && /\/profiles\/\d+\/documents$/.test(response.url()),
  );
  // Native form.submit bypasses both constraint validation and the Stimulus submit guard.
  await page.getByTestId('document-upload-form').evaluate((form) => HTMLFormElement.prototype.submit.call(form));
  const response = await rejectedUpload;
  expect(response.status()).toBe(422);
  expect(await response.finished()).toBeNull();
  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await expect(page.getByTestId('document-form-errors')).toContainText('50');
  await page.getByRole('link', { name: 'Cancel', exact: true }).click();
  await expect(page).toHaveURL(/\/profiles\/\d+\/documents$/);
  await expect(page.locator('[data-testid^="document-row-"]').filter({ hasText: 'browser-server-limit-' })).toHaveCount(0);
});

test('duplicate bytes are rejected without replacing originals while new content and another profile remain allowed', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  const originalFile = {
    name: 'browser-duplicate-original.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from('An original duplicate-boundary browser document.'),
  };
  await page.getByTestId('document-file-field').setInputFiles([
    originalFile,
    { ...originalFile, name: 'browser-duplicate-same-batch.txt' },
  ]);
  await page.getByTestId('document-upload-submit').click();
  await expect(page).toHaveURL(/\/profiles\/\d+\/documents$/);
  await expect(page.getByTestId('flash-notice')).toContainText('1 document uploaded');
  await expect(page.getByTestId('flash-alert')).toContainText('browser-duplicate-same-batch.txt');
  await expect(page.getByTestId('flash-alert')).toContainText(/already|duplicate/i);
  await expect(page.getByRole('link', { name: /browser-duplicate-same-batch/ })).toHaveCount(0);
  const originalLink = page.getByRole('link', { name: /browser-duplicate-original/ });
  await expect(originalLink).toHaveCount(1);
  const originalPath = await originalLink.getAttribute('href');

  await page.getByTestId('documents-add-link').click();
  await page.getByTestId('document-file-field').setInputFiles({ ...originalFile, name: 'browser-duplicate-renamed.txt' });
  await page.getByTestId('document-upload-submit').click();
  await expect(page).toHaveURL(/\/profiles\/\d+\/documents\/new$/);
  await expect(page.getByTestId('document-form-errors')).toContainText(/already|duplicate/i);

  await page.getByTestId('document-file-field').setInputFiles({
    ...originalFile,
    buffer: Buffer.from('Different bytes under the same duplicate-boundary filename.'),
  });
  await page.getByTestId('document-upload-submit').click();
  await expect(page).toHaveURL(/\/profiles\/\d+\/documents$/);
  await expect(page.getByTestId('flash-notice')).toContainText('1 document uploaded');
  await expect(page.getByRole('link', { name: /browser-duplicate-original/ })).toHaveCount(2);
  await expect(page.getByRole('link', { name: /browser-duplicate-renamed/ })).toHaveCount(0);
  const originalDownload = await page.request.get(`${originalPath}/original`);
  expect(originalDownload.ok()).toBe(true);
  expect(await originalDownload.body()).toEqual(originalFile.buffer);

  await page.goto('/dashboard');
  await page.getByTestId('dashboard-add-profile').click();
  await page.locator('#dependent_first_name').fill('Duplicate');
  await page.locator('#dependent_last_name').fill('Boundary');
  await page.getByTestId('profile-create-submit').click();
  await expect(page.getByRole('heading', { name: 'Duplicate Boundary' })).toBeVisible();
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();
  await page.getByTestId('document-file-field').setInputFiles(originalFile);
  await page.getByTestId('document-upload-submit').click();
  await expect(page.getByRole('heading', { name: "Duplicate Boundary's Documents" })).toBeVisible();
  await expect(page.getByTestId('flash-notice')).toContainText('1 document uploaded');
  await expect(page.getByRole('link', { name: /browser-duplicate-original/ })).toHaveCount(1);
});

test('editing document with blank title shows a validation error', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await expect(page).toHaveURL(/\/profiles\/\d+\/documents$/);
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await page.getByRole('link', { name: /Advance Directive|QA Planning Document/ }).first().click();
  await page.getByTestId('document-edit-link').click();

  await page.getByTestId('document-title-field').fill('');
  await page.getByTestId('document-save-submit').click();

  await expect(page.getByRole('heading', { name: 'Edit Document' })).toBeVisible();
  await expect(page.getByTestId('document-form-errors')).toContainText("Title can't be blank");
});
