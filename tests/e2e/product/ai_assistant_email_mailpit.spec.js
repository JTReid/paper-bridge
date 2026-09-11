// @ts-check
import { test, expect } from '../fixtures';
import { signIn } from '../helpers/auth';
import { createAnswerEmailScenario, deleteAnswerEmailScenario } from '../helpers/ai_assistant_email';
import { clearMailpit, expectNoMailpitMessages, waitForMailpitMessage } from '../helpers/mailpit';

test.skip(!process.env.QA_MAILPIT_API_URL, 'Mailpit QA mode only');

let scenario;

test.beforeEach(async ({ request }) => {
  await clearMailpit(request);
  scenario = createAnswerEmailScenario();
});

test.afterEach(() => {
  if (scenario) deleteAnswerEmailScenario(scenario.profileId);
  scenario = undefined;
});

async function openEmail(page) {
  await signIn(page);
  await page.goto(`/profiles/${scenario.profileId}/ai-assistant`);
  await page.getByTestId('ai-assistant-email-answer').click();
  await expect(page.getByRole('dialog', { name: 'Email answer', exact: true })).toBeVisible();
}

test('answer email delivers the existing response without source documents or private links', async ({ page, request }) => {
  await openEmail(page);
  await page.getByTestId('ai-assistant-email-recipient-email').fill('outside-advocate@example.test');
  const messageBody = 'Please review this before our meeting.';
  await page.getByTestId('ai-assistant-email-message').fill(messageBody);
  await page.getByTestId('ai-assistant-email-submit').click();
  await expect(page.getByRole('dialog')).toContainText('Answer emailed to outside-advocate@example.test.');

  const email = await waitForMailpitMessage(request, (candidate) =>
    candidate.To?.some((recipient) => recipient.Address === 'outside-advocate@example.test'));
  expect(email.From.Address).toBe('support@paperbridgeadvocacy.com');
  expect(email.Attachments).toBe(0);
  const response = await request.get(`${process.env.QA_MAILPIT_API_URL}/api/v1/message/${email.ID}`);
  expect(response.ok()).toBeTruthy();
  const message = await response.json();
  expect(message.To.map((recipient) => recipient.Address)).toEqual(['outside-advocate@example.test']);
  expect(message.ReplyTo.map((recipient) => recipient.Address)).toEqual([scenario.senderEmail]);
  expect(message.Attachments).toEqual([]);
  const text = message.Text.replaceAll('\r\n', '\n');
  expect(text).toContain(scenario.question);
  expect(text).toContain(scenario.answer);
  expect(text).toContain(scenario.limitation);
  expect(text).toContain(messageBody);
  expect(text).toContain(scenario.sourceTitle);
  expect(text).toMatch(/\[1\].*Classroom support evaluation.*(?:page|p\.) 2/i);
  expect(text).toMatch(/Sep(?:tember)? 0?2, 2026/);
  for (const body of [text, message.HTML]) {
    expect(body).not.toContain(scenario.sourceQuote);
    expect(body).not.toContain('Original source file must never be emailed');
    expect(body).not.toMatch(/\/(?:documents|profiles|rails\/active_storage)\//);
  }
  expect(message.HTML).toContain(scenario.question);
  expect(message.HTML).toContain(scenario.limitation);
  expect(message.HTML).toContain(scenario.sourceTitle);
});

test('invalid recipient sends no answer email', async ({ page, request }) => {
  await openEmail(page);
  const response = await page.request.post(`/profiles/${scenario.profileId}/ai-assistant/${scenario.queryId}/email`, {
    form: {
      'ai_assistant_email[recipient_email]': 'not-an-email',
      'ai_assistant_email[message]': 'Should not be sent.',
    },
  });
  expect(response.status()).toBe(422);
  await expectNoMailpitMessages(request);
});
