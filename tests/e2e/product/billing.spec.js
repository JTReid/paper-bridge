// @ts-check
import { test, expect } from '../fixtures';
import { QA_USER, signIn } from '../helpers/auth';
import { setAccountSubscription } from '../helpers/backend';
import { expectAccessible } from '../helpers/accessibility';

const ACCOUNT_NAME = 'Greenfield Family';
const ACTIVE_SUBSCRIPTION = {
  status: 'active',
  stripe_customer_id: 'cus_qa_browser',
  stripe_subscription_id: 'sub_qa_browser',
  stripe_price_id: 'price_qa_browser',
};
const INACTIVE_SUBSCRIPTION = {
  status: 'incomplete',
  stripe_customer_id: 'cus_qa_incomplete',
  stripe_subscription_id: null,
  stripe_price_id: 'price_qa_browser',
};

test.afterEach(() => {
  setAccountSubscription(ACCOUNT_NAME, ACTIVE_SUBSCRIPTION);
});

test('inactive account is limited to billing and checkout form uses full-page navigation', async ({ page }) => {
  setAccountSubscription(ACCOUNT_NAME, INACTIVE_SUBSCRIPTION);

  await signInWithoutDashboardExpectation(page);

  await expect(page).toHaveURL(/\/billing$/);
  await expect(page.getByTestId('billing-page')).toBeVisible();
  await expect(page.getByTestId('billing-status')).toContainText('Subscription required');
  await expect(page.locator('body')).toContainText('Not active');
  await expect(page.locator('body')).not.toContainText(/cus_qa_incomplete|price_qa_browser/);
  await expect(page.getByTestId('nav-billing')).toBeVisible();
  await expect(page.getByTestId('nav-dashboard')).toHaveCount(0);
  await expect(page.getByTestId('nav-dependents')).toHaveCount(0);

  const checkoutForm = page.locator('form[action="/billing/checkout_session"]');
  await expect(checkoutForm).toHaveAttribute('data-turbo', 'false');
  await expect(page.getByTestId('subscribe-button')).toBeVisible();

  await page.goto('/dashboard');
  await expect(page).toHaveURL(/\/billing$/);
  await expect(page.getByTestId('flash-alert')).toContainText('A subscription is required to continue.');
  await expectAccessible(page);
});

test('active account can use product and billing portal form uses full-page navigation', async ({ page }) => {
  setAccountSubscription(ACCOUNT_NAME, ACTIVE_SUBSCRIPTION);

  await signIn(page);
  await expect(page.getByTestId('nav-dashboard')).toBeVisible();
  await expect(page.getByTestId('nav-dependents')).toBeVisible();

  await page.goto('/billing');
  await expect(page.getByTestId('billing-status')).toContainText('Subscription active');

  const portalForm = page.locator('form[action="/billing/portal_session"]');
  await expect(portalForm).toHaveAttribute('data-turbo', 'false');
  await expect(page.getByTestId('manage-subscription-button')).toHaveText(/Manage Subscription/);
  await expectAccessible(page);
});

async function signInWithoutDashboardExpectation(page) {
  await page.goto('/users/sign_in');
  await page.getByTestId('sign-in-email').fill(QA_USER.email);
  await page.getByTestId('sign-in-password').fill(QA_USER.password);
  await page.getByTestId('sign-in-submit').click();
}
