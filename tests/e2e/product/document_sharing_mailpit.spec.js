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

  expect(email.From.Address).toBe('support@paperbridgeadvocacy.com');
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

test('sharing multiple selected documents delivers both original attachments through Mailpit', async ({ page, request }) => {
  const attemptId = Date.now();
  const subject = `QA Mailpit bulk share ${attemptId}`;
  const files = [
    { name: `qa-mailpit-bulk-first-${attemptId}.txt`, mimeType: 'text/plain', buffer: Buffer.from('First original document for bulk sharing.\r\n') },
    { name: `qa-mailpit-bulk-second-${attemptId}.txt`, mimeType: 'text/plain', buffer: Buffer.from('Second original document for bulk sharing.\r\n') },
  ];

  await openDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();
  await page.getByTestId('document-file-field').setInputFiles(files);
  await page.getByTestId('document-upload-submit').click();
  await expect(page.getByTestId('flash-notice')).toContainText('2 documents uploaded and being prepared.');

  for (const file of files) {
    const row = page.locator('[data-testid^="document-row-"]').filter({ hasText: file.name });
    await row.getByRole('checkbox').check();
  }
  const firstSelectedRow = page.locator('[data-testid^="document-row-"]').filter({ hasText: files[0].name });
  await firstSelectedRow.locator('[data-testid^="document-share-button-"]').click();
  await expect(page.locator('[data-document-share-target="selectedSummary"]')).toHaveText('2 documents selected');
  await page.getByTestId('document-share-recipient-select').selectOption('therapist@example.test');
  await page.getByTestId('document-share-subject').fill(subject);
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
  expect(email.Attachments).toBe(2);

  const messageUrl = `${process.env.QA_MAILPIT_API_URL}/api/v1/message/${email.ID}`;
  const response = await request.get(messageUrl);
  expect(response.ok()).toBeTruthy();
  const message = await response.json();
  expect(message.Attachments.map((attachment) => attachment.FileName).sort()).toEqual(files.map((file) => file.name).sort());

  for (const file of files) {
    const attachment = message.Attachments.find((candidate) => candidate.FileName === file.name);
    const download = await request.get(`${messageUrl}/part/${attachment.PartID}`);
    expect(download.ok()).toBeTruthy();
    expect(await download.body()).toEqual(file.buffer);
  }
});
