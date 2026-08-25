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
  metadata: {},
};
const INACTIVE_SUBSCRIPTION = {
  status: 'incomplete',
  stripe_customer_id: 'cus_qa_incomplete',
  stripe_subscription_id: null,
  stripe_price_id: 'price_qa_browser',
  metadata: {},
};
const PENDING_SUBSCRIPTION = {
  ...INACTIVE_SUBSCRIPTION,
  metadata: { checkout_pending: true },
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
  await expect(page.getByTestId('nav-dependents')).toHaveCount(0);

  await page.goto('/billing');
  await expect(page.getByTestId('billing-status')).toContainText('Subscription active');

  const portalForm = page.locator('form[action="/billing/portal_session"]');
  await expect(portalForm).toHaveAttribute('data-turbo', 'false');
  await expect(page.getByTestId('manage-subscription-button')).toHaveText(/Manage Subscription/);
  await expectAccessible(page);
});

test('successful checkout waits safely and Turbo opens the dashboard after activation', async ({ page }) => {
  setAccountSubscription(ACCOUNT_NAME, PENDING_SUBSCRIPTION);
  await signInWithoutDashboardExpectation(page);

  await page.goto('/dashboard?checkout=success');

  await expect(page).toHaveURL(/\/dashboard\?checkout=success$/);
  await expect(page.getByTestId('checkout-pending-page')).toBeVisible();
  await expect(page.locator('turbo-cable-stream-source')).toHaveCount(1);
  await expect(page.getByTestId('dashboard-calendar-link')).toHaveCount(0);
  await expectAccessible(page);

  setAccountSubscription(ACCOUNT_NAME, ACTIVE_SUBSCRIPTION);
  await deliverTurboRefresh(page);

  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByTestId('flash-notice')).toContainText('Your PaperBridge subscription is active.');
  await expect(page.getByTestId('dashboard-calendar-link')).toBeVisible();
});

test('non-active checkout result returns to billing after the webhook refresh', async ({ page }) => {
  setAccountSubscription(ACCOUNT_NAME, PENDING_SUBSCRIPTION);
  await signInWithoutDashboardExpectation(page);
  await page.goto('/dashboard?checkout=success');
  await expect(page.getByTestId('checkout-pending-page')).toBeVisible();

  setAccountSubscription(ACCOUNT_NAME, INACTIVE_SUBSCRIPTION);
  await deliverTurboRefresh(page);

  await expect(page).toHaveURL(/\/billing$/);
  await expect(page.getByTestId('flash-alert')).toContainText('Your subscription isn’t active yet.');
});

test('canceled checkout returns to billing with a clear notice', async ({ page }) => {
  setAccountSubscription(ACCOUNT_NAME, PENDING_SUBSCRIPTION);
  await signInWithoutDashboardExpectation(page);

  await page.goto('/billing?checkout=cancel');

  await expect(page).toHaveURL(/\/billing$/);
  await expect(page.getByTestId('flash-notice')).toContainText('Checkout canceled.');
});

async function signInWithoutDashboardExpectation(page) {
  await page.goto('/users/sign_in');
  await page.getByTestId('sign-in-email').fill(QA_USER.email);
  await page.getByTestId('sign-in-password').fill(QA_USER.password);
  await page.getByTestId('sign-in-submit').click();
  await expect(page).toHaveURL(/\/billing$/);
  await expect(page.getByTestId('billing-page')).toBeVisible();
}

async function deliverTurboRefresh(page) {
  await page.evaluate(() => {
    document.body.insertAdjacentHTML('beforeend', '<turbo-stream action="refresh"></turbo-stream>');
  });
}
