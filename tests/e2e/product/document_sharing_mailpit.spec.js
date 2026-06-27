// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';
import {
  clearMailpit,
  expectNoMailpitMessages,
  getMailpitMessageText,
  waitForMailpitMessage,
} from '../helpers/mailpit';

test.skip(!process.env.QA_MAILPIT_API_URL, 'Mailpit QA mode only');

test.beforeEach(async ({ request }) => {
  await clearMailpit(request);
});

test('document sharing sends an email captured by Mailpit', async ({ page, request }) => {
  const subject = `QA Mailpit share ${Date.now()}`;
  const messageBody = 'Sent from the Mailpit QA harness.';

  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();

  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await page.locator('[data-testid^="document-share-button-"]').first().click();

  await page.getByTestId('document-share-recipient-select').selectOption('therapist@example.test');
  await page.getByTestId('document-share-subject').fill(subject);
  await page.getByTestId('document-share-message').fill(messageBody);
  await page.getByTestId('document-share-submit').click();

  await expect(page.getByTestId('flash-notice')).toContainText('Documents shared with therapist@example.test');

  const email = await waitForMailpitMessage(
    request,
    (candidate) => (
      candidate.Subject === subject &&
      candidate.To?.some((recipient) => recipient.Address === 'therapist@example.test')
    ),
    { timeoutMs: 8000 },
  );

  expect(email.From.Address).toBe('from@example.com');
  expect(email.Attachments).toBe(1);
  expect(email.Snippet).toContain('PaperBridge document');

  const text = await getMailpitMessageText(request, email.ID);
  expect(text).toContain(messageBody);
  expect(text).toContain('Advance Directive');
});

test('document sharing with no selected documents does not send email', async ({ page, request }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();

  const dependentId = page.url().match(/\/dependents\/(\d+)\/documents/)?.[1];
  expect(dependentId).toBeTruthy();

  const response = await page.request.post(`/share_events?dependent_id=${dependentId}`, {
    form: {
      'share_event[recipient_email]': 'therapist@example.test',
      'share_event[subject]': 'Should not send',
      'share_event[message]': 'No document selected',
    },
  });

  expect(response.ok()).toBeTruthy();
  await expectNoMailpitMessages(request);
});

test('document sharing with a blank recipient stays in the browser and sends no email', async ({ page, request }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.locator('[data-testid^="document-share-button-"]').first().click();

  await page.getByTestId('document-share-submit').click();

  await expect(page.getByRole('dialog', { name: 'Share Documents' })).toBeVisible();
  expect(await page.getByTestId('document-share-recipient-email').evaluate((input) => input.validity.valueMissing)).toBe(true);
  await expectNoMailpitMessages(request);
});

test('document sharing with malformed recipient is rejected before email delivery', async ({ page, request }) => {
  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();

  const documentId = await page.locator('[data-testid^="document-share-checkbox-"]').first().inputValue();
  const dependentId = page.url().match(/\/dependents\/(\d+)\/documents/)?.[1];
  expect(dependentId).toBeTruthy();

  const response = await page.request.post(`/share_events?dependent_id=${dependentId}`, {
    form: {
      'share_event[recipient_email]': 'not-an-email',
      'share_event[subject]': 'Should not send',
      'share_event[message]': 'Malformed recipient',
      'share_event[document_ids][]': documentId,
    },
  });

  expect(response.ok()).toBeTruthy();
  await expectNoMailpitMessages(request);
});
