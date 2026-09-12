// @ts-check
import { test, expect } from '../fixtures';
import { signIn } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';
import { createDocumentListScenario, deleteDocumentListScenario, updateListDocument } from '../helpers/document_list_updates';

let scenario;

test.beforeEach(async () => { scenario = createDocumentListScenario(); });
test.afterEach(async () => {
  if (scenario) deleteDocumentListScenario(scenario.profileId);
  scenario = undefined;
});

test('upload completion updates rows and counts while keeping the share dialog, selection and unfinished search', async ({ page }) => {
  await signIn(page);
  await page.goto(`/profiles/${scenario.profileId}/documents/new`);
  await page.getByTestId('document-file-field').setInputFiles({
    name: 'uploaded-record.txt', mimeType: 'text/plain', buffer: Buffer.from('Synthetic uploaded source for document list updates.'),
  });
  await page.getByTestId('document-upload-submit').click();
  await expect(page).toHaveURL(`/profiles/${scenario.profileId}/documents`);
  const uploadedRow = page.locator('[data-testid^="document-row-"]').filter({ hasText: 'uploaded-record.txt' });
  await expect(uploadedRow).toContainText('Getting ready');
  const uploadedId = Number((await uploadedRow.getAttribute('data-testid')).replace('document-row-', ''));
  await uploadedRow.getByRole('checkbox').check();
  await page.getByTestId('documents-search-field').fill('an unfinished search');
  await page.getByTestId('documents-selection-share').click();
  await page.getByTestId('document-share-recipient-email').fill('teacher@example.test');
  await page.getByTestId('document-share-message').fill('Keep these notes while processing finishes.');

  await applySignals(page, updateListDocument(scenario.profileId, uploadedId, { status: 'processed', category: 'medical' }));

  await expect(uploadedRow).toContainText('Ready');
  await expect(uploadedRow).toContainText('Medical');
  await expect(uploadedRow.getByRole('checkbox')).toBeChecked();
  await expect(page.getByTestId('documents-total-count')).toHaveText('4');
  await expect(page.getByTestId('documents-ready-count')).toHaveText('1');
  await expect(page.getByTestId('documents-processing-count')).toHaveText('3');
  await expect(page.getByTestId('documents-selection-count')).toHaveText('1 of 4 selected');
  await expect(page.getByTestId('documents-search-field')).toHaveValue('an unfinished search');
  await expect(page.getByTestId('document-share-dialog')).toBeVisible();
  await expect(page.getByTestId('document-share-recipient-email')).toHaveValue('teacher@example.test');
  await expect(page.getByTestId('document-share-message')).toHaveValue('Keep these notes while processing finishes.');
  await expect(page.getByTestId('document-share-message')).toBeFocused();
  await page.getByTestId('document-share-close').click();
  await expectAccessible(page);
});

test('background updates respect committed filename and category filters as documents enter and leave the list', async ({ page }) => {
  await signIn(page);
  const url = `/profiles/${scenario.profileId}/documents?category=medical&q=alpha`;
  await page.goto(url);
  await expect(page.getByRole('heading', { name: 'No documents found' })).toBeVisible();
  await expect(page.getByTestId('documents-selection-bar')).toBeHidden();
  await page.getByTestId('documents-search-field').fill('still typing');
  const alpha = scenario.documents[0];
  const beta = scenario.documents[1];

  await applySignals(page, updateListDocument(scenario.profileId, beta.id, { status: 'processed', category: 'medical' }));
  await expect(page.getByRole('heading', { name: 'No documents found' })).toBeVisible();
  await applySignals(page, updateListDocument(scenario.profileId, alpha.id, { status: 'processed', category: 'medical' }));

  await expect(page.getByTestId(`document-row-${alpha.id}`)).toContainText('Ready');
  await expect(page.getByTestId(`document-row-${beta.id}`)).toHaveCount(0);
  await expect(page.getByTestId('documents-total-count')).toHaveText('1');
  await expect(page.getByTestId('documents-selection-bar')).toBeVisible();
  await expect(page.getByTestId('documents-category-filter-medical')).toHaveAttribute('aria-current', 'page');
  await expect(page.getByTestId('documents-search-field')).toHaveValue('still typing');
  await expect(page).toHaveURL(url);

  await page.getByTestId(`document-share-checkbox-${alpha.id}`).check();
  await applySignals(page, updateListDocument(scenario.profileId, alpha.id, { category: 'therapy' }));
  await expect(page.getByRole('heading', { name: 'No documents found' })).toBeVisible();
  await expect(page.getByTestId('documents-total-count')).toHaveText('0');
  await expect(page.getByTestId('documents-selection-bar')).toBeHidden();
  await expect(page.getByTestId('documents-search-field')).toHaveValue('still typing');
});

test('refreshes coalesce and retain a selection changed while the request is pending', async ({ page }) => {
  await signIn(page);
  await page.goto(`/profiles/${scenario.profileId}/documents`);
  await waitForInitialRefresh(page);
  const [alpha, beta] = scenario.documents;
  await page.getByTestId(`document-share-checkbox-${alpha.id}`).check();
  let release;
  let refreshCount = 0;
  const held = new Promise((resolve) => { release = resolve; });
  await page.route(`**/profiles/${scenario.profileId}/documents*`, async (route) => {
    if (!route.request().headers().accept?.includes('text/vnd.turbo-stream.html')) return route.continue();
    refreshCount += 1;
    if (refreshCount === 1) await held;
    await route.continue();
  });

  try {
    const signals = updateListDocument(scenario.profileId, alpha.id, { status: 'processed', category: 'educational' });
    await applySignals(page, signals);
    await expect.poll(() => refreshCount).toBe(1);
    await applySignals(page, signals);
    await applySignals(page, signals);
    await page.getByTestId(`document-share-checkbox-${beta.id}`).check();
    release();

    await expect(page.getByTestId(`document-row-${alpha.id}`)).toContainText('Ready');
    await expect.poll(() => refreshCount).toBe(2);
    await waitForInitialRefresh(page);
    await expect(page.getByTestId(`document-share-checkbox-${alpha.id}`)).toBeChecked();
    await expect(page.getByTestId(`document-share-checkbox-${beta.id}`)).toBeChecked();
    await expect(page.getByTestId(`document-share-checkbox-${beta.id}`)).toBeFocused();
    await expect(page.getByTestId('documents-selection-count')).toHaveText('2 of 3 selected');
    expect(refreshCount).toBe(2);

    const row = page.getByTestId(`document-row-${alpha.id}`);
    await row.getByRole('link').focus();
    await applySignals(page, updateListDocument(scenario.profileId, alpha.id, { category: 'medical' }));
    await expect(row).toContainText('Medical');
    await expect(row.getByRole('link')).toBeFocused();
    await row.getByRole('button').focus();
    await applySignals(page, updateListDocument(scenario.profileId, alpha.id, { category: 'therapy' }));
    await expect(row).toContainText('Therapy');
    await expect(row.getByRole('button')).toBeFocused();
  } finally {
    release();
    await page.unrouteAll({ behavior: 'wait' });
  }
});

test('a Cable connection reconciles a completion missed before subscription and preserves an open delete dialog', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await signIn(page);
  await page.goto(`/profiles/${scenario.profileId}/documents`);
  await waitForInitialRefresh(page);
  const alpha = scenario.documents[0];
  await page.getByTestId(`document-share-checkbox-${alpha.id}`).check();
  await page.getByTestId('documents-selection-delete').click();
  const stream = page.locator('turbo-cable-stream-source[data-document-list-target="stream"]');
  await stream.evaluate((element) => element.removeAttribute('connected'));
  updateListDocument(scenario.profileId, alpha.id, { status: 'failed' });
  await stream.evaluate((element) => element.setAttribute('connected', ''));

  await expect(page.getByTestId(`document-row-${alpha.id}`)).toContainText('Needs attention');
  await expect(page.getByTestId('documents-processing-count')).toHaveText('2');
  await expect(page.getByTestId('documents-delete-dialog')).toBeVisible();
  await expect(page.getByTestId('documents-delete-list')).toContainText('alpha-record.txt');
  await expect(page.getByTestId('documents-delete-cancel')).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(page.getByTestId('documents-delete-dialog')).toBeHidden();
  await expectAccessible(page);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});

async function applySignals(page, signals) {
  expect(signals.length).toBeGreaterThan(0);
  // Test Cable adapters are process-local; deliver the model's real signal to
  // Turbo, which then fetches and renders the server's current filtered list.
  await page.evaluate((messages) => messages.forEach((message) => window.Turbo.renderStreamMessage(message)), signals);
}

async function waitForInitialRefresh(page) {
  await expect.poll(() => page.evaluate(() => {
    const element = document.querySelector('[data-controller="document-list"]');
    const controller = window.Stimulus.getControllerForElementAndIdentifier(element, 'document-list');
    return Boolean(controller?.connected && controller.streamTarget.hasAttribute('connected') && !controller.request);
  })).toBe(true);
}
