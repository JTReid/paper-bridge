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

async function backToSeededDocuments(page) {
  await page.getByRole('link', { name: /Back to documents/ }).click();
  await expect(page.getByRole('heading', { name: "Avery Morgan's Documents" })).toBeVisible();
}

test('QA seeded document list exposes lifecycle edge states', async ({ page }) => {
  await openSeededDocuments(page);

  await expect(documentRow(page, 'QA Medical Intake Summary')).toContainText('Ready');
  await expect(documentRow(page, 'QA Edge Uploaded Only')).toContainText('Uploaded');
  await expect(documentRow(page, 'QA Edge Queued Document')).toContainText('Getting ready');
  await expect(documentRow(page, 'QA Edge Processing Document')).toContainText('Preparing');
  await expect(documentRow(page, 'QA Edge Preparation Failed')).toContainText('Needs attention');
  await expect(documentRow(page, 'QA Edge Missing Embeddings')).toContainText('Ready');
  await expect(documentRow(page, 'QA Edge Partial Embeddings')).toContainText('Ready');
  await expect(documentRow(page, 'QA Edge No Summary')).toContainText('Ready');

  await expectAccessible(page);
});

test('QA seeded empty and failed document details render safely', async ({ page }) => {
  await openSeededDocuments(page);
  await page.getByRole('link', { name: /QA Edge Uploaded Only/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge Uploaded Only' })).toBeVisible();
  await expect(page.getByTestId('document-processing-status')).toContainText('Uploaded');
  await expect(page.getByText('A summary isn’t available yet.')).toBeVisible();
  await expect(page.getByText('View document text')).toHaveCount(0);
  const openOriginal = page.getByTestId('document-open-original');
  await expect(openOriginal).toBeVisible();
  await expect(openOriginal).toHaveAttribute('href', /\/documents\/\d+\/original$/);
  await expect(openOriginal).toHaveAttribute('target', '_blank');
  await expect(openOriginal).toHaveAttribute('rel', 'noopener');
  await expect(page.getByTestId('document-processing-status').getByTestId('document-open-original')).toHaveCount(0);
  await expect(openOriginal.locator('..').getByTestId('document-edit-link')).toBeVisible();
  await expectAccessible(page);

  await backToSeededDocuments(page);
  await page.getByRole('link', { name: /QA Edge Preparation Failed/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge Preparation Failed' })).toBeVisible();
  await expect(page.getByTestId('document-processing-status')).toContainText('Needs attention');
  await expect(page.getByText('We couldn’t prepare a summary for this file.')).toBeVisible();
  await expect(page.getByText('Synthetic QA preparation failure.')).toHaveCount(0);
  await expect(page.getByText('View document text')).toHaveCount(0);
});

test('QA seeded processing stats describe customer-ready outcomes', async ({ page }) => {
  await openSeededDocuments(page);
  await page.getByRole('link', { name: /QA Edge Missing Embeddings/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge Missing Embeddings' })).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-pages')).toContainText('2');
  await expect(page.getByTestId('document-processing-stat-ask-paperbridge')).toContainText('Not ready');
  await expect(page.getByText('Chunks', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Embeddings', { exact: true })).toHaveCount(0);

  await backToSeededDocuments(page);
  await page.getByRole('link', { name: /QA Edge Partial Embeddings/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge Partial Embeddings' })).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-pages')).toContainText('2');
  await expect(page.getByTestId('document-processing-stat-ask-paperbridge')).toContainText('Not ready');

  await backToSeededDocuments(page);
  await page.getByRole('link', { name: /QA Edge No Summary/ }).click();

  await expect(page.getByRole('heading', { name: 'QA Edge No Summary' })).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-summary')).toContainText('Not ready');
  await expect(page.getByTestId('document-processing-stat-ask-paperbridge')).toContainText('Ready');
  await expect(page.getByText('A summary isn’t available yet.')).toBeVisible();
});
