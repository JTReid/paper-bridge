// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';
import {
  clearAiAssistantQueries,
  completeLatestAiAssistantQueryWithoutBroadcast,
  resetLatestAiAssistantQueryStart,
} from '../helpers/backend';

test.beforeEach(() => clearAiAssistantQueries('Greenfield Family'));
test.afterEach(() => clearAiAssistantQueries('Greenfield Family'));

test('ai assistant loads without submitting a query', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-ai-assistant-link').click();

  await expect(page.getByRole('heading', { name: 'Ask PaperBridge' })).toBeVisible();
  await expect(page.getByText('Suggested questions')).toBeVisible();
  await expect(page.getByText('Based on your records')).toBeVisible();
  await expect(page.getByText('Most answers begin appearing within about 30 seconds.')).toBeVisible();
  await expect(page.getByPlaceholder('Ask a question about documents, care progress, or next steps...')).toBeVisible();
  await expectAccessible(page);
});

test('ai assistant shows immediate progress and queues without leaving the profile', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-ai-assistant-link').click();
  await expect(page).toHaveURL(/\/profiles\/\d+\/ai-assistant$/);
  const assistantPath = new URL(page.url()).pathname;

  // This test deliberately resets queue state before reload; do not let periodic reconciliation start it first.
  await page.locator('[data-controller~="ai-assistant-query"]').evaluate((element) => {
    element.setAttribute('data-ai-assistant-query-reconcile-every-value', '60000');
  });

  await page.route(/\/profiles\/\d+\/ai-assistant$/, async (route) => {
    if (route.request().method() === 'POST') {
      await new Promise((resolve) => setTimeout(resolve, 400));
    }
    await route.continue();
  });

  await page.getByTestId('ai-assistant-query').fill('What changed in the latest records?');
  const startRequest = page.waitForResponse((response) =>
    response.request().method() === 'POST' && /\/ai-assistant\/\d+\/start$/.test(response.url()),
  );
  await page.getByTestId('ai-assistant-submit').click();

  await expect(page.getByTestId('ai-assistant-immediate-progress')).toBeVisible();
  await expect(page.getByText('Starting your question…')).toBeVisible();
  await expect(page.getByTestId('ai-assistant-query-result')).toHaveAttribute('data-phase', 'queued');
  const startResponse = await startRequest;
  expect(startResponse.status()).toBe(202);
  expect(await startResponse.finished()).toBeNull();
  await expect(page.getByText('What changed in the latest records?')).toBeVisible();
  await expect(page.getByTestId('ai-assistant-submit')).toBeDisabled();
  await expect(page.getByTestId('ai-assistant-query')).toHaveAttribute('readonly', '');
  expect(new URL(page.url()).pathname).toBe(assistantPath);
  expect(page.url()).not.toContain('q=');
  await expect(page.getByText('Emma Greenfield').first()).toBeVisible();
  await expectAccessible(page);

  resetLatestAiAssistantQueryStart('Greenfield Family');
  const restartedRequest = page.waitForResponse((response) =>
    response.request().method() === 'POST' && /\/ai-assistant\/\d+\/start$/.test(response.url()),
  );
  await page.reload();
  const restartedResponse = await restartedRequest;
  expect(restartedResponse.status()).toBe(202);
  expect(await restartedResponse.finished()).toBeNull();
  await expect(page.getByTestId('ai-assistant-query-result')).toHaveAttribute('data-phase', 'queued');
});

test('ai assistant reconciles a finished answer when its Cable update is missed', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-ai-assistant-link').click();

  await page.getByTestId('ai-assistant-query').fill('What changed while I was away?');
  const startRequest = page.waitForResponse((response) =>
    response.request().method() === 'POST' && /\/ai-assistant\/\d+\/start$/.test(response.url()),
  );
  await page.getByTestId('ai-assistant-submit').click();
  expect((await startRequest).status()).toBe(202);

  completeLatestAiAssistantQueryWithoutBroadcast(
    'Greenfield Family',
    'This answer was restored from the durable query.',
  );

  await expect(page.getByText('This answer was restored from the durable query.')).toBeVisible();
  await expect(page.getByTestId('ai-assistant-query-result')).toHaveAttribute('data-phase', 'completed');
  await expect(page.getByTestId('ai-assistant-submit')).toBeEnabled();
});

test('ai assistant retries the same query when its start response is ambiguous', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-ai-assistant-link').click();

  await page.evaluate(() => {
    const fetchFromServer = window.fetch.bind(window);
    const startUrls = [];
    let dropFirstStartResponse = true;

    document.documentElement.dataset.testStartUrls = '[]';
    window.fetch = async (input, options) => {
      const url = input instanceof Request ? input.url : input.toString();
      if (!/\/ai-assistant\/\d+\/start$/.test(url)) return fetchFromServer(input, options);

      startUrls.push(url);
      document.documentElement.dataset.testStartUrls = JSON.stringify(startUrls);
      const response = await fetchFromServer(input, options);

      if (dropFirstStartResponse) {
        dropFirstStartResponse = false;
        await response.text();
        throw new TypeError('Simulated lost start response');
      }

      return response;
    };
  });

  await page.getByTestId('ai-assistant-query').fill('Did the start request work?');
  await page.getByTestId('ai-assistant-submit').click();

  await expect(page.getByText('Still getting your question started…')).toBeVisible();
  await expect(page.getByTestId('ai-assistant-submit')).toBeDisabled();
  await expect.poll(async () => JSON.parse(
    await page.locator('html').getAttribute('data-test-start-urls') || '[]',
  ).length).toBe(2);
  const startUrls = JSON.parse(
    await page.locator('html').getAttribute('data-test-start-urls') || '[]',
  );
  expect(new Set(startUrls).size).toBe(1);
  await expect(page.getByTestId('ai-assistant-query-result')).toHaveAttribute('data-active', 'true');
  await expect(page.getByTestId('ai-assistant-submit')).toBeDisabled();
});

test('ai assistant ignores a stale status response after a newer update', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-ai-assistant-link').click();

  let staleStatusCaptured = () => {};
  const statusCaptured = new Promise((resolve) => { staleStatusCaptured = resolve; });
  let releaseStaleStatus = () => {};
  const statusReleased = new Promise((resolve) => { releaseStaleStatus = resolve; });
  let heldFirstStatus = false;

  await page.route(/\/profiles\/\d+\/ai-assistant\/\d+\/status$/, async (route) => {
    if (heldFirstStatus) {
      await route.continue();
      return;
    }

    heldFirstStatus = true;
    const staleResponse = await route.fetch();
    staleStatusCaptured();
    await statusReleased;
    await route.fulfill({ response: staleResponse });
  });

  await page.getByTestId('ai-assistant-query').fill('Could an old status overwrite a new one?');
  await page.getByTestId('ai-assistant-submit').click();
  await statusCaptured;

  await page.getByTestId('ai-assistant-query-result').evaluate((query) => {
    query.dataset.queryVersion = '9999-12-31T23:59:59.999999Z';
    query.dataset.phase = 'newer-update';
    const status = query.querySelector('[data-ai-assistant-start-status]');
    if (status) status.textContent = 'A newer update is already on screen.';
  });

  const statusResponse = page.waitForResponse(/\/profiles\/\d+\/ai-assistant\/\d+\/status$/);
  releaseStaleStatus();
  await statusResponse;
  await page.waitForTimeout(100);

  await expect(page.getByTestId('ai-assistant-query-result')).toHaveAttribute('data-phase', 'newer-update');
  await expect(page.getByText('A newer update is already on screen.')).toBeVisible();
});

test('ai assistant does not retry a definitive start rejection', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-ai-assistant-link').click();

  await page.evaluate(() => {
    const fetchFromServer = window.fetch.bind(window);
    let startAttempts = 0;

    document.documentElement.dataset.testStartAttempts = '0';
    window.fetch = async (input, options) => {
      const url = input instanceof Request ? input.url : input.toString();
      if (!/\/ai-assistant\/\d+\/start$/.test(url)) return fetchFromServer(input, options);

      startAttempts += 1;
      document.documentElement.dataset.testStartAttempts = startAttempts.toString();
      return new Response('', { status: 422 });
    };
  });

  await page.getByTestId('ai-assistant-query').fill('Will this rejected start retry?');
  await page.getByTestId('ai-assistant-submit').click();

  await expect(
    page.getByTestId('ai-assistant-query-result')
      .getByText('We couldn’t start that question. Please refresh and try again.'),
  ).toBeVisible();
  await expect(page.getByTestId('ai-assistant-query-result')).toHaveAttribute('data-active', 'false');
  await expect(page.getByTestId('ai-assistant-submit')).toBeEnabled();
  await page.waitForTimeout(2_500);
  await expect(page.locator('html')).toHaveAttribute('data-test-start-attempts', '1');
});

test('ai assistant bounds temporary start retries', async ({ page }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-ai-assistant-link').click();

  await page.locator('[data-controller~="ai-assistant-query"]').evaluate((element) => {
    element.setAttribute('data-ai-assistant-query-start-retry-after-value', '25');
    element.setAttribute('data-ai-assistant-query-start-retry-max-attempts-value', '2');

    const fetchFromServer = window.fetch.bind(window);
    let startAttempts = 0;
    document.documentElement.dataset.testStartAttempts = '0';

    window.fetch = async (input, options) => {
      const url = input instanceof Request ? input.url : input.toString();
      if (!/\/ai-assistant\/\d+\/start$/.test(url)) return fetchFromServer(input, options);

      startAttempts += 1;
      document.documentElement.dataset.testStartAttempts = startAttempts.toString();
      return new Response('', { status: 503 });
    };
  });

  await page.getByTestId('ai-assistant-query').fill('How long will starting retry?');
  await page.getByTestId('ai-assistant-submit').click();

  await expect(
    page.getByTestId('ai-assistant-query-result')
      .getByText('We couldn’t start that question. Please refresh and try again.'),
  ).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('data-test-start-attempts', '3');
  await page.waitForTimeout(200);
  await expect(page.locator('html')).toHaveAttribute('data-test-start-attempts', '3');
  await expect(page.getByTestId('ai-assistant-submit')).toBeEnabled();
});
