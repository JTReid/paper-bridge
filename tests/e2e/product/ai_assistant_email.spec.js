// @ts-check
import { test, expect } from '../fixtures';
import { signIn } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';
import {
  createAnswerEmailScenario,
  deleteAnswerEmailScenario,
  answerEmailScenarioState,
} from '../helpers/ai_assistant_email';

let scenario;

test.beforeEach(() => {
  scenario = createAnswerEmailScenario();
});

test.afterEach(() => {
  if (scenario) deleteAnswerEmailScenario(scenario.profileId);
  scenario = undefined;
});

async function openEmail(page) {
  await signIn(page);
  await page.goto(`/profiles/${scenario.profileId}/ai-assistant`);
  await expect(page.getByTestId('ai-assistant-save-answer')).toBeVisible();
  await page.getByTestId('ai-assistant-email-answer').click();
  await expect(page.getByRole('dialog', { name: 'Email answer', exact: true })).toBeVisible();
}

function expectQueryUnchanged() {
  expect(answerEmailScenarioState(scenario.profileId)).toEqual({
    queryCount: 1,
    savedAnswerCount: 0,
    answer: scenario.originalAnswer,
  });
}

test('emails a completed answer to any address without saving it or asking AI again', async ({ page }) => {
  const aiRequests = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' && /\/ai-assistant(?:\/\d+\/start)?$/.test(new URL(request.url()).pathname)) {
      aiRequests.push(request.url());
    }
  });
  await openEmail(page);
  await page.getByTestId('ai-assistant-email-recipient-email').fill('outside-advocate@example.test');
  await page.getByTestId('ai-assistant-email-message').fill('Please review this before our meeting.');
  let releaseSend = () => {};
  const sendReleased = new Promise((resolve) => { releaseSend = resolve; });
  await page.route(`**/ai-assistant/${scenario.queryId}/email`, async (route) => {
    await sendReleased;
    await route.continue();
  });
  await page.getByTestId('ai-assistant-email-submit').click();
  await expect(page.getByTestId('ai-assistant-email-submit')).toBeDisabled();
  await expect(page.getByTestId('ai-assistant-email-submit')).toHaveValue('Sending…');
  releaseSend();

  const dialog = page.getByRole('dialog', { name: 'Email answer', exact: true });
  await expect(dialog).toContainText('Answer emailed to outside-advocate@example.test.');
  await dialog.getByRole('button', { name: 'Done', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await expect(page.getByTestId('ai-assistant-email-answer')).toBeFocused();
  await expect(page).toHaveURL(new RegExp(`/profiles/${scenario.profileId}/ai-assistant$`));
  await expect(page.getByText('Offer a quiet arrival.')).toBeVisible();
  await page.getByTestId('research-nav-saved-answers').click();
  await expect(page).toHaveURL(new RegExp(`/profiles/${scenario.profileId}/saved-answers$`));
  await page.goBack();
  await expect(page.getByTestId('ai-assistant-email-answer')).toBeVisible();
  await expect(page.getByRole('dialog', { name: 'Email answer', exact: true })).not.toBeVisible();
  expect(aiRequests).toEqual([]);
  expectQueryUnchanged();
});

test('Care Team contact is an optional shortcut and the recipient remains editable', async ({ page }) => {
  await openEmail(page);
  const contacts = page.getByTestId('ai-assistant-email-recipient-select');
  await expect(contacts.locator('option')).toHaveCount(2);
  await expect(contacts.locator('option').filter({ hasText: 'Alex Teacher' })).toHaveAttribute('value', scenario.contactEmail);
  await contacts.selectOption(scenario.contactEmail);
  await expect(page.getByTestId('ai-assistant-email-recipient-email')).toHaveValue(scenario.contactEmail);
  await page.getByTestId('ai-assistant-email-recipient-email').fill('another-recipient@example.test');
  await page.getByTestId('ai-assistant-email-submit').click();
  await expect(page.getByRole('dialog')).toContainText('Answer emailed to another-recipient@example.test.');
  expectQueryUnchanged();
});

test('server validation preserves the email and message in the open dialog', async ({ page }) => {
  await openEmail(page);
  await page.getByTestId('ai-assistant-email-recipient-email').fill('not-an-email');
  await page.getByTestId('ai-assistant-email-message').fill('Keep this note while I fix the recipient.');
  await page.getByRole('dialog').locator('form').evaluate((form) => { form.noValidate = true; });
  const rejected = page.waitForResponse((response) => response.request().method() === 'POST'
    && new URL(response.url()).pathname === `/profiles/${scenario.profileId}/ai-assistant/${scenario.queryId}/email`);
  await page.getByTestId('ai-assistant-email-submit').click();
  expect((await rejected).status()).toBe(422);
  await expect(page.getByRole('dialog', { name: 'Email answer', exact: true })).toBeVisible();
  await expect(page.getByTestId('ai-assistant-email-recipient-email')).toHaveValue('not-an-email');
  await expect(page.getByTestId('ai-assistant-email-message')).toHaveValue('Keep this note while I fix the recipient.');
  await expect(page.getByRole('alert')).toContainText(/email/i);
  await expect(page.getByTestId('ai-assistant-email-submit')).toBeEnabled();
  await page.getByTestId('ai-assistant-email-recipient-email').fill('corrected@example.test');
  await page.getByTestId('ai-assistant-email-submit').click();
  await expect(page.getByRole('dialog')).toContainText('Answer emailed to corrected@example.test.');
  expectQueryUnchanged();
});

test('email dialog fits a phone, passes axe, and restores focus after Escape and closing', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await openEmail(page);
  const dialog = page.getByRole('dialog', { name: 'Email answer', exact: true });
  await expectAccessible(page);
  const bounds = await dialog.boundingBox();
  expect(bounds).not.toBeNull();
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(390);
  expect(bounds.y).toBeGreaterThanOrEqual(0);
  expect(bounds.y + bounds.height).toBeLessThanOrEqual(844);
  await page.getByTestId('ai-assistant-email-message').fill('An unfinished note.');
  await page.keyboard.press('Escape');
  await expect(dialog).not.toBeVisible();
  await expect(page.getByTestId('ai-assistant-email-answer')).toBeFocused();
  await page.getByTestId('ai-assistant-email-answer').click();
  await expect(dialog).toBeVisible();
  await page.getByTestId('ai-assistant-email-close').click();
  await expect(dialog).not.toBeVisible();
  await expect(page.getByTestId('ai-assistant-email-answer')).toBeFocused();
  expectQueryUnchanged();
});
