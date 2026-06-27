// @ts-check
import { test, expect } from '../fixtures';
import { openSeededDependentWorkspace } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';

function documentRow(page, title) {
  return page.locator('[data-testid^="document-row-"]').filter({ hasText: title });
}

async function openSeededDocuments(page) {
  await openSeededDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await expect(page.getByRole('heading', { name: "Avery Morgan's Documents" })).toBeVisible();
}

test('QA seeded document list exposes lifecycle edge states', async ({ page }) => {
  await openSeededDocuments(page);

  await expect(documentRow(page, 'QA Medical Intake Summary')).toContainText('Processed');
  await expect(documentRow(page, 'QA Edge Uploaded Only')).toContainText('Uploaded');
  await expect(documentRow(page, 'QA Edge Queued Document')).toContainText('Queued');
  await expect(documentRow(page, 'QA Edge Processing Document')).toContainText('Processing');
  await expect(documentRow(page, 'QA Edge Preparation Failed')).toContainText('Failed');
  await expect(documentRow(page, 'QA Edge Missing Embeddings')).toContainText('Processed');
  await expect(documentRow(page, 'QA Edge Partial Embeddings')).toContainText('Processed');
  await expect(documentRow(page, 'QA Edge No Summary')).toContainText('Processed');

  await expectAccessible(page);
});

test('QA seeded empty and failed document details render safely', async ({ page }) => {
  await openSeededDocuments(page);
  await page.getByRole('link', { name: /QA Edge Uploaded Only/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge Uploaded Only' })).toBeVisible();
  await expect(page.getByTestId('document-processing-status')).toContainText('Uploaded');
  await expect(page.getByText('No chunks have been created yet.')).toBeVisible();
  await expect(page.getByText('No summary has been generated yet.')).toBeVisible();
  await expectAccessible(page);

  await page.getByRole('link', { name: /Back to documents/ }).click();
  await page.getByRole('link', { name: /QA Edge Preparation Failed/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge Preparation Failed' })).toBeVisible();
  await expect(page.getByTestId('document-processing-status')).toContainText('Failed');
  await expect(page.getByText('Synthetic QA preparation failure.')).toBeVisible();
  await expect(page.getByText('No chunks have been created yet.')).toBeVisible();
});

test('QA seeded partial processing stats expose missing embedding states', async ({ page }) => {
  await openSeededDocuments(page);
  await page.getByRole('link', { name: /QA Edge Missing Embeddings/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge Missing Embeddings' })).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-chunks')).toContainText('2');
  await expect(page.getByTestId('document-processing-stat-embeddings')).toContainText('0');
  await expect(page.getByTestId('document-processing-stat-pages')).toContainText('2');

  await page.getByRole('link', { name: /Back to documents/ }).click();
  await page.getByRole('link', { name: /QA Edge Partial Embeddings/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge Partial Embeddings' })).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-chunks')).toContainText('3');
  await expect(page.getByTestId('document-processing-stat-embeddings')).toContainText('1');
  await expect(page.getByTestId('document-processing-stat-pages')).toContainText('2');

  await page.getByRole('link', { name: /Back to documents/ }).click();
  await page.getByRole('link', { name: /QA Edge No Summary/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge No Summary' })).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-embeddings')).toContainText('1');
  await expect(page.getByText('No summary has been generated yet.')).toBeVisible();
});
