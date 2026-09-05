// @ts-check
import { readFileSync } from 'node:fs';
import { test, expect } from '../fixtures';
import { expectAccessible } from '../helpers/accessibility';
import { deleteAccountsAndUsers, setAccountSubscription } from '../helpers/backend';

const sampleFile = readFileSync('test/fixtures/files/sample.txt');

const ACCOUNTS = {
  complete: {
    accountName: 'Onboarding Tour Complete Family',
    email: 'onboarding-tour-complete@example.test',
  },
  dismiss: {
    accountName: 'Onboarding Tour Dismiss Family',
    email: 'onboarding-tour-dismiss@example.test',
  },
  mobile: {
    accountName: 'Onboarding Tour Mobile Family',
    email: 'onboarding-tour-mobile@example.test',
  },
  multi: {
    accountName: 'Onboarding Tour Multi Family',
    email: 'onboarding-tour-multi@example.test',
  },
};

const ACTIVE_SUBSCRIPTION = {
  status: 'active',
  stripe_customer_id: null,
  stripe_subscription_id: null,
  stripe_price_id: 'price_onboarding_tour',
  metadata: {},
};

test.beforeEach(() => {
  deleteAccountsAndUsers(Object.values(ACCOUNTS));
});

test.afterEach(() => {
  deleteAccountsAndUsers(Object.values(ACCOUNTS));
});

test('new customer completes the guided path from signup through their first question', async ({ page }) => {
  const account = ACCOUNTS.complete;
  await registerAndOpenDashboard(page, account);

  await expectTourStep(page, 1, 'Create your first Profile');
  await expect(page.locator('body')).toHaveClass(/driver-simple/);
  await expectAccessible(page);

  await page.getByTestId('dashboard-add-profile').click();
  await expect(page).toHaveURL(/\/dependents\/new$/);
  await expectTourStep(page, 1, 'Add their details');

  // Exercise server validation and tour recovery despite the browser's required-field check.
  await page.getByTestId('profile-create-form').evaluate((form) => form.setAttribute('novalidate', ''));
  await page.getByTestId('profile-create-submit').click();
  await expect(page).toHaveURL(/\/dependents\/new$/);
  await expect(page.getByRole('alert')).toContainText('prevented this profile from saving');
  await expectTourStep(page, 1, 'Add their details');
  await expect.poll(async () => (await tourState(page))?.phase).toBe('profile_form');

  await page.getByTestId('product-tour-action').click();
  await expect(page.locator('#dependent_first_name')).toBeFocused();
  await page.locator('#dependent_first_name').fill('Jamie');
  await page.locator('#dependent_last_name').fill('Tour');
  await page.getByTestId('profile-create-submit').click();
  await expect(page).toHaveURL(/\/dependents\/\d+$/);
  await expectTourStep(page, 2, 'Open Documents');

  await page.getByTestId('dependent-documents-link').click();
  await expectTourStep(page, 3, 'Add documents');

  await page.getByTestId('documents-add-link').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/documents\/new$/);
  await expectTourStep(page, 4, 'Choose your files');

  const fileChooserPromise = page.waitForEvent('filechooser');
  await page.getByTestId('product-tour-action').click();
  const fileChooser = await fileChooserPromise;
  await fileChooser.setFiles({
    name: 'unsupported-onboarding.svg',
    mimeType: 'image/svg+xml',
    buffer: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
  });
  await expectTourStep(page, 4, 'Ready to upload');
  await expect(page.getByTestId('document-upload-submit')).toHaveClass(/driver-active-element/);
  await page.getByTestId('document-upload-submit').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/documents\/new$/);
  await expect(page.getByTestId('document-form-errors')).toBeVisible();
  await expectTourStep(page, 4, 'Choose your files');
  await expect.poll(async () => (await tourState(page))?.phase).toBe('choose_files');

  await page.getByTestId('document-file-field').setInputFiles({
    name: 'onboarding-record.txt',
    mimeType: 'text/plain',
    buffer: sampleFile,
  });
  await expectTourStep(page, 4, 'Ready to upload');
  await page.getByTestId('product-tour-action').click();
  await expect(page.getByTestId('document-file-list')).toBeFocused();
  await expect(page.getByTestId('document-file-summary')).toContainText('1 file selected');

  let unexpectedFileChoosers = 0;
  const countUnexpectedFileChooser = () => { unexpectedFileChoosers += 1; };
  page.on('filechooser', countUnexpectedFileChooser);
  await page.getByTestId('document-file-remove-0').click();
  await expectTourStep(page, 4, 'Choose your files');
  await expect.poll(async () => tourState(page)).toMatchObject({ status: 'active', phase: 'choose_files' });
  await expect(page.getByTestId('document-file-summary')).toContainText('No files selected');
  expect(unexpectedFileChoosers).toBe(0);
  page.off('filechooser', countUnexpectedFileChooser);

  await page.getByTestId('document-file-field').setInputFiles({
    name: 'onboarding-record.txt',
    mimeType: 'text/plain',
    buffer: sampleFile,
  });
  await expectTourStep(page, 4, 'Ready to upload');
  await page.getByTestId('document-upload-submit').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expect(page.getByTestId('flash-notice')).toContainText('1 document uploaded and being prepared.');
  await expectTourStep(page, 5, 'Open Ask PaperBridge');

  await page.getByTestId('documents-ask-ai-link').click();
  await expect(page).toHaveURL(/\/dependents\/\d+\/ai-assistant$/);
  await expectTourStep(page, 6, 'Ask your first question');

  await page.getByTestId('ai-assistant-submit').click();
  await expect(page.getByTestId('flash-alert')).toContainText("Question can't be blank");
  await expectTourStep(page, 6, 'Ask your first question');
  await expect.poll(async () => (await tourState(page))?.phase).toBe('ask_question');

  await page.getByTestId('product-tour-action').click();
  await expect(page.getByTestId('ai-assistant-query')).toBeFocused();
  await page.getByTestId('ai-assistant-query').fill('What should I review first?');
  await page.getByTestId('ai-assistant-submit').click();
  await expect(page.getByText('What should I review first?')).toBeVisible();
  await expect(page.getByTestId('product-tour-popover')).toHaveCount(0);

  const state = await tourState(page);
  expect(state).toMatchObject({ version: 1, status: 'completed', phase: 'completed' });
  expect(JSON.stringify(state)).not.toContain('Jamie Tour');
  expect(JSON.stringify(state)).not.toContain('onboarding-record.txt');
  expect(JSON.stringify(state)).not.toContain('What should I review first?');
  const accountId = await page.getByTestId('app-shell').getAttribute('data-product-tour-account-id-value');
  expect(await tourStorageKey(page)).toBe(`paperbridge:getting-started:v1:account:${accountId}`);

  await page.reload();
  await expect(page.getByTestId('product-tour-popover')).toHaveCount(0);

  await page.getByTestId('product-tour-replay').click();
  await expect(page).toHaveURL(/\/dashboard$/);
  await expectTourStep(page, 1, 'Open a Profile');
  await expect.poll(async () => (await tourState(page))?.phase).toBe('open_profile');
});

test('multiple files return directly to Documents and a suggested question completes the tour', async ({ page }) => {
  await registerAndOpenDashboard(page, ACCOUNTS.multi);
  await page.getByTestId('dashboard-add-profile').click();
  await page.locator('#dependent_first_name').fill('Morgan');
  await page.locator('#dependent_last_name').fill('Multi');
  await page.getByTestId('profile-create-submit').click();
  await page.getByTestId('dependent-documents-link').click();
  await page.getByTestId('documents-add-link').click();

  const files = [
    { name: 'multi-one.txt', mimeType: 'text/plain', buffer: sampleFile },
    { name: 'multi-two.txt', mimeType: 'text/plain', buffer: sampleFile },
  ];
  await page.getByTestId('document-file-field').setInputFiles(files);
  await expectTourStep(page, 4, 'Ready to upload');
  await page.getByTestId('product-tour-action').click();
  await expect(page.getByTestId('document-file-list')).toBeFocused();
  await page.getByTestId('document-file-clear-selection').click();
  await expectTourStep(page, 4, 'Choose your files');
  await expect.poll(async () => tourState(page)).toMatchObject({ status: 'active', phase: 'choose_files' });
  await expect(page.getByTestId('document-file-summary')).toContainText('No files selected');
  expect(await page.getByTestId('document-file-field').evaluate((input) => input.files.length)).toBe(0);

  await page.getByTestId('document-file-field').setInputFiles(files);
  await expectTourStep(page, 4, 'Ready to upload');
  await page.getByTestId('document-upload-submit').click();

  await expect(page).toHaveURL(/\/dependents\/\d+\/documents$/);
  await expectTourStep(page, 5, 'Open Ask PaperBridge');
  await page.getByTestId('documents-ask-ai-link').click();
  await expectTourStep(page, 6, 'Ask your first question');

  await page.getByRole('button', { name: 'What are the most important updates across these documents?' }).click();
  await expect(page.getByText('What are the most important updates across these documents?')).toBeVisible();
  await expect(page.getByTestId('product-tour-popover')).toHaveCount(0);
  await expect.poll(async () => (await tourState(page))?.status).toBe('completed');
});

test('skipping stays dismissed until the customer replays the tour', async ({ page }) => {
  const account = ACCOUNTS.dismiss;
  await registerAndOpenDashboard(page, account);
  await expectTourStep(page, 1, 'Create your first Profile');

  await page.getByTestId('product-tour-close').click();
  await expect(page.getByTestId('product-tour-popover')).toHaveCount(0);
  await expect.poll(async () => (await tourState(page))?.status).toBe('dismissed');

  await page.reload();
  await expect(page.getByTestId('product-tour-popover')).toHaveCount(0);

  await page.getByTestId('product-tour-replay').click();
  await expect(page).toHaveURL(/\/dashboard$/);
  await expectTourStep(page, 1, 'Create your first Profile');
  await expect.poll(async () => (await tourState(page))?.status).toBe('active');

  await page.keyboard.press('Escape');
  await expect(page.getByTestId('product-tour-popover')).toHaveCount(0);
  await expect.poll(async () => (await tourState(page))?.status).toBe('dismissed');
});

test('first tooltip fits a phone viewport without horizontal overflow', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await registerAndOpenDashboard(page, ACCOUNTS.mobile);
  await expectTourStep(page, 1, 'Create your first Profile');

  const popover = page.getByTestId('product-tour-popover');
  const box = await popover.boundingBox();
  expect(box).not.toBeNull();
  expect(box?.x).toBeGreaterThanOrEqual(0);
  expect((box?.x || 0) + (box?.width || 0)).toBeLessThanOrEqual(390);
  await expect(page.getByTestId('product-tour-close')).toHaveAttribute('aria-label', 'Skip setup tour');
});

async function registerAndOpenDashboard(page, account) {
  await page.goto('/users/sign_up');
  await page.getByTestId('registration-account-name').fill(account.accountName);
  await page.getByTestId('registration-name').fill('Onboarding Tour Admin');
  await page.getByTestId('registration-email').fill(account.email);
  await page.getByTestId('registration-password').fill('password');
  await page.getByTestId('registration-password-confirmation').fill('password');
  await page.getByTestId('registration-submit').click();

  await expect(page).toHaveURL(/\/billing$/);
  setAccountSubscription(account.accountName, ACTIVE_SUBSCRIPTION);
  await page.goto('/dashboard?checkout=success');
  await expect(page).toHaveURL(/\/dashboard$/);
}

async function expectTourStep(page, number, title) {
  const popover = page.getByTestId('product-tour-popover');
  await expect(popover).toBeVisible();
  await expect(popover).toContainText(`Step ${number} of 6`);
  await expect(popover).toContainText(title);
}

async function tourState(page) {
  const key = await tourStorageKey(page);

  return page.evaluate((storageKey) =>
    storageKey ? JSON.parse(window.localStorage.getItem(storageKey) || 'null') : null,
  key);
}

async function tourStorageKey(page) {
  return page.evaluate(() => {
    return Object.keys(window.localStorage).find((candidate) =>
      candidate.startsWith('paperbridge:getting-started:v1:account:'),
    ) || null;
  });
}
