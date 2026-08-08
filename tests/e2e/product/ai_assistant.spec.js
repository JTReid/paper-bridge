// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';
import { clearAiAssistantQueries, resetLatestAiAssistantQueryStart } from '../helpers/backend';

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
  await expect(page).toHaveURL(/\/dependents\/\d+\/ai-assistant$/);
  const assistantPath = new URL(page.url()).pathname;

  await page.route(/\/dependents\/\d+\/ai-assistant$/, async (route) => {
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
