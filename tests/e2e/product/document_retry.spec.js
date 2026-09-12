// @ts-check
import { test, expect } from '../fixtures';
import { signIn } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';
import { createDocumentRetryScenario, documentRetryState, finishDocumentRetry, deleteDocumentRetryScenario } from '../helpers/document_retry';

let scenario;

test.beforeEach(() => { scenario = createDocumentRetryScenario(); });
test.afterEach(() => {
  if (scenario) deleteDocumentRetryScenario(scenario.profileId);
  scenario = undefined;
});

test('a failed document keeps its generated summary until retry rebuilds it and finishes search preparation', async ({ page }) => {
  const before = documentRetryState(scenario.profileId);
  expect(before.searchableIds).toEqual([]);
  await signIn(page);
  await page.goto(`/documents/${scenario.documentId}`);
  await expect(page.getByTestId('document-retry-processing')).toBeVisible();
  await expect(page.getByText('Summary from the earlier attempt.')).toBeVisible();
  await expect(page.getByText('Earlier summary key point.')).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-summary')).toContainText('Ready');
  await expect(page.getByTestId('document-processing-stat-ask-paperbridge')).toContainText('Unavailable');
  await expectAccessible(page);
  const originalPath = await page.getByTestId('document-download-original').getAttribute('href');

  let release = () => {};
  const held = new Promise((resolve) => { release = resolve; });
  await page.route(`**/documents/${scenario.documentId}/retry_processing`, async (route) => {
    await held;
    await route.continue();
  });
  try {
    await page.getByTestId('document-retry-processing').click();
    await expect(page.getByTestId('document-retry-processing')).toBeDisabled();
    await expect(page.getByTestId('document-retry-processing')).toHaveText('Queuing…');
  } finally {
    release();
  }
  await expect(page.getByTestId('flash-notice')).toHaveText('Document queued for processing.');
  await expect(page).toHaveURL(`/documents/${scenario.documentId}`);
  await expect(page.getByTestId('document-retry-processing')).toHaveCount(0);
  await expect(page.getByTestId('document-processing-stat-ask-paperbridge')).toContainText('Getting ready');
  await expect(page.getByText('Summary from the earlier attempt.')).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-summary')).toContainText('Ready');
  await expect(page.getByTestId('document-download-original')).toHaveAttribute('href', originalPath);

  const queued = documentRetryState(scenario.profileId);
  expect(queued.status).toBe('queued');
  expect(queued.searchableIds).toEqual([]);
  expect(queued.preserved).toEqual(before.preserved);
  expect(queued.pageIds).toEqual(before.pageIds); // The destructive reset belongs to worker start.
  expect(queued.summary).toEqual(before.summary);
  expect(queued.summarizedAt).toEqual(before.summarizedAt);

  const finished = finishDocumentRetry(scenario.profileId);
  expect(finished.requests).toEqual(['document_chunks', 'document_summary', 'embeddings', 'timeline_events']);
  // Test Cable broadcasts are process-local, so deliver the real worker's
  // captured detail updates in processing order without reloading the page.
  expect(finished.beforeSummary.state.status).toBe('processing');
  expect(finished.beforeSummary.state.summary).toEqual({});
  expect(finished.beforeSummary.state.summarizedAt).toBeNull();
  expect(finished.beforeSummary.state.searchableIds).toEqual([]);
  await page.evaluate((messages) => messages.forEach((message) => window.Turbo.renderStreamMessage(message)), finished.beforeSummary.broadcasts);
  await expect(page.getByText('Summary from the earlier attempt.')).toHaveCount(0);
  await expect(page.getByText('Earlier summary key point.')).toHaveCount(0);
  await expect(page.getByText('Your summary will appear when it’s ready.')).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-summary')).toContainText('Getting ready');

  expect(finished.afterSummary.state.status).toBe('processing');
  expect(finished.afterSummary.state.summary.summary).toBe('Fresh summary after retry.');
  expect(finished.afterSummary.state.searchableIds).toEqual([]);
  await page.evaluate((messages) => messages.forEach((message) => window.Turbo.renderStreamMessage(message)), finished.afterSummary.broadcasts);
  await expect(page.getByText('Fresh summary after retry.')).toBeVisible();
  await expect(page.getByText('Rebuilt from the saved original.')).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-summary')).toContainText('Ready');
  await expect(page.getByTestId('document-processing-stat-ask-paperbridge')).toContainText('Getting ready');

  await page.evaluate((messages) => messages.forEach((message) => window.Turbo.renderStreamMessage(message)), finished.broadcasts);

  await expect(page.getByText('Fresh summary after retry.')).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-ask-paperbridge')).toContainText('Ready');
  await expect(page.getByTestId('document-retry-processing')).toHaveCount(0);
  await expect(page.getByRole('heading', { name: 'Family edited title' })).toBeVisible();
  expect(finished.state.status).toBe('processed');
  expect(finished.state.preserved).toEqual(before.preserved);
  expect(finished.state.searchableIds).toEqual([scenario.documentId]);
  for (const key of ['pageIds', 'chunkIds', 'embeddingIds', 'timelineIds']) {
    expect(finished.state[key]).toHaveLength(1);
    expect(finished.state[key][0]).not.toBe(before[key][0]);
  }
  expect(finished.state.runs).toContainEqual([scenario.historyId, 'failed']);
  expect(finished.state.runs).toHaveLength(2);
  expect(finished.state.runs[1][1]).toBe('completed');

  await page.goto(`/profiles/${scenario.profileId}/saved-answers/${scenario.savedAnswerId}`);
  await expect(page.getByText('Keep this saved answer during processing.')).toBeVisible();
});

test('retry control fits a phone and queued documents offer no second retry', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await signIn(page);
  await page.goto(`/documents/${scenario.documentId}`);
  await expect(page.getByTestId('document-retry-processing')).toBeVisible();
  await expectAccessible(page);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);

  await page.getByTestId('document-retry-processing').click();
  await expect(page.getByTestId('flash-notice')).toHaveText('Document queued for processing.');
  await page.reload();
  await expect(page.getByTestId('document-retry-processing')).toHaveCount(0);
  await expect(page.getByText('Summary from the earlier attempt.')).toBeVisible();
  await expect(page.getByTestId('document-processing-stat-summary')).toContainText('Ready');
  expect(documentRetryState(scenario.profileId).status).toBe('queued');
});
