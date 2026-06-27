// @ts-check
import { test, expect } from '../fixtures';
import { signIn } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';

test('fixture admin signs in to the dashboard', async ({ page }) => {
  await signIn(page);

  await expect(page.getByRole('heading', { name: 'Good to see you.' })).toBeVisible();
  await expect(page.getByText('Family Calendar')).toBeVisible();
  await expect(page.getByText('No upcoming events')).toBeVisible();
  await expectAccessible(page);
});

test('invalid sign in stays on sign in and shows an alert', async ({ page }) => {
  await page.goto('/users/sign_in');
  await page.getByTestId('sign-in-email').fill('admin@example.test');
  await page.getByTestId('sign-in-password').fill('not-the-password');
  await page.getByTestId('sign-in-submit').click();

  await expect(page.getByRole('heading', { name: 'Sign in', exact: true })).toBeVisible();
  await expect(page.getByTestId('flash-alert')).toContainText(/Invalid email or password/i);
});
