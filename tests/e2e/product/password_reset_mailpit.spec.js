// @ts-check
import { test, expect } from '../fixtures';
import { deleteAccountsAndUsers } from '../helpers/backend';
import { clearMailpit, waitForMailpitMessage } from '../helpers/mailpit';

test.skip(!process.env.QA_MAILPIT_API_URL, 'Mailpit QA mode only');

const createdAccounts = [];

test.beforeEach(async ({ request }) => {
  await clearMailpit(request);
});

test.afterEach(() => {
  if (createdAccounts.length) deleteAccountsAndUsers(createdAccounts.splice(0));
});

test('password reset email opens locally and the new password replaces the old password', async ({ page, request }) => {
  const account = {
    accountName: `Password Reset QA ${Date.now()}`,
    email: `password-reset-${Date.now()}@example.test`,
  };
  createdAccounts.push(account);

  await page.goto('/users/sign_up');
  await page.getByTestId('registration-account-name').fill(account.accountName);
  await page.getByTestId('registration-name').fill('Password Reset Tester');
  await page.getByTestId('registration-email').fill(account.email);
  await page.getByTestId('registration-password').fill('original-password');
  await page.getByTestId('registration-password-confirmation').fill('original-password');
  await page.getByTestId('registration-submit').click();
  await expect(page).toHaveURL(/\/billing$/);
  await page.context().clearCookies();

  await page.goto('/users/sign_in');
  await page.getByRole('link', { name: 'Forgot your password?' }).click();
  await expect(page.getByRole('heading', { name: 'Forgot your password?' })).toBeVisible();
  await page.getByLabel('Email', { exact: true }).fill(account.email);
  await page.getByRole('button', { name: 'Send me password reset instructions' }).click();
  await expect(page.getByTestId('flash-notice')).toContainText('reset your password');

  const email = await waitForMailpitMessage(request, (candidate) => (
    candidate.Subject === 'Reset password instructions' &&
    candidate.To?.some((recipient) => recipient.Address === account.email)
  ));
  expect(email.From.Address).toBe('support@paperbridgeadvocacy.com');

  const response = await request.get(`${process.env.QA_MAILPIT_API_URL}/api/v1/message/${email.ID}`);
  expect(response.ok()).toBeTruthy();
  const message = await response.json();
  const resetUrl = message.HTML.match(/href="([^"]*reset_password_token[^"]*)"/)?.[1]?.replaceAll('&amp;', '&');
  expect(resetUrl).toBeTruthy();
  expect(new URL(resetUrl).origin).toBe(new URL(page.url()).origin);

  await page.goto(resetUrl);
  await page.getByLabel('New password', { exact: true }).fill('updated-password');
  await page.getByLabel('Confirm new password', { exact: true }).fill('updated-password');
  await page.getByRole('button', { name: 'Change my password' }).click();
  await expect(page).toHaveURL(/\/billing$/);
  await page.context().clearCookies();

  await page.goto('/users/sign_in');
  await page.getByTestId('sign-in-email').fill(account.email);
  await page.getByTestId('sign-in-password').fill('original-password');
  await page.getByTestId('sign-in-submit').click();
  await expect(page.getByTestId('flash-alert')).toContainText(/Invalid email or password/i);

  await page.getByTestId('sign-in-password').fill('updated-password');
  await page.getByTestId('sign-in-submit').click();
  await expect(page).toHaveURL(/\/billing$/);
});
