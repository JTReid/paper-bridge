// @ts-check
import { randomUUID } from 'node:crypto';
import { test, expect } from '../fixtures';
import { QA_USER, signIn } from '../helpers/auth';
import { createAccountProfiles, deleteAccountProfilesByLastName, setAccountSubscription } from '../helpers/backend';
import { expectAccessible } from '../helpers/accessibility';

const ACCOUNT_NAME = 'Greenfield Family';
const ACTIVE_SUBSCRIPTION = {
  status: 'active',
  stripe_customer_id: 'cus_qa_browser',
  stripe_subscription_id: 'sub_qa_browser',
  stripe_price_id: 'price_qa_browser',
  profile_limit: null,
  trial_end: null,
  launch_trial_used_at: null,
  current_period_end: null,
  cancel_at_period_end: false,
  stripe_subscription_event_created_at: null,
  metadata: {},
};
const INACTIVE_SUBSCRIPTION = {
  status: 'incomplete',
  stripe_customer_id: 'cus_qa_incomplete',
  stripe_subscription_id: null,
  stripe_price_id: 'price_qa_browser',
  profile_limit: null,
  stripe_subscription_event_created_at: null,
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

test('trial billing shows the future allowance price and removes the payment promise after cancellation', async ({ page }) => {
  const trialEnd = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  const trialSubscription = {
    ...ACTIVE_SUBSCRIPTION,
    status: 'trialing',
    profile_limit: 6,
    trial_end: trialEnd,
    current_period_end: trialEnd,
    launch_trial_used_at: new Date().toISOString(),
  };
  setAccountSubscription(ACCOUNT_NAME, trialSubscription);

  await signIn(page);
  await page.goto('/billing');

  const trialDetails = page.getByTestId('billing-trial-details');
  await expect(trialDetails).toContainText('$0 during your free trial.');
  await expect(trialDetails).toContainText('After the trial: $30 USD/month for your current allowance of 6 managed profiles.');
  await expect(trialDetails).toContainText('First payment is scheduled for');
  await expect(page.getByTestId('manage-subscription-button')).toBeVisible();
  await expect(page.getByTestId('subscribe-button')).toHaveCount(0);
  await expect(page.getByTestId('launch-trial-offer')).toHaveCount(0);
  await expectAccessible(page);

  // Synthetic post-webhook state, not a request to Stripe's live portal.
  setAccountSubscription(ACCOUNT_NAME, { ...trialSubscription, cancel_at_period_end: true });
  await page.reload();

  await expect(trialDetails).toContainText('Your subscription is set to cancel at the end of the trial and will not renew.');
  await expect(trialDetails).not.toContainText('First payment is scheduled for');
  await expect(trialDetails).not.toContainText('After the trial:');
  await expect(page.getByText('Will not renew', { exact: true })).toBeVisible();
});

test('profile allowance blocks additions, permits purchased extras, and preserves profiles after a reduction', async ({ page }) => {
  test.setTimeout(60_000);
  const lastName = `Billing Allowance ${randomUUID()}`;

  try {
    setAccountSubscription(ACCOUNT_NAME, { ...ACTIVE_SUBSCRIPTION, profile_limit: 5 });
    createAccountProfiles(ACCOUNT_NAME, [
      { first_name: 'Allowance First', last_name: lastName },
      { first_name: 'Allowance Second', last_name: lastName },
    ]);
    await signIn(page);
    await expect(page.getByTestId('profile-allowance')).toContainText('4 of 5 managed profiles in use.');

    await page.getByTestId('dashboard-add-profile').click();
    await page.locator('#dependent_first_name').fill('Allowance Fifth');
    await page.locator('#dependent_last_name').fill(lastName);
    await page.getByTestId('profile-create-submit').click();
    await expect(page.getByRole('heading', { name: `Allowance Fifth ${lastName}`, exact: true })).toBeVisible();

    await page.goto('/profiles/new');
    await expect(page.getByTestId('profile-allowance')).toContainText('5 of 5 managed profiles in use.');
    await expect(page.getByTestId('profile-limit-reached')).toContainText('Your profile allowance is full.');
    await expect(page.getByTestId('profile-create-submit')).toBeDisabled();
    await expectAccessible(page);
    await page.getByTestId('profile-allowance-billing-link').click();
    await expect(page).toHaveURL(/\/billing$/);
    await expect(page.getByTestId('profile-allowance')).toContainText('5 of 5 managed profiles in use.');
    await expect(page.getByTestId('manage-subscription-button')).toBeVisible();

    // Synthetic webhook state: Stripe has approved a sixth profile. This test
    // deliberately does not open hosted Checkout or perform a Stripe charge.
    setAccountSubscription(ACCOUNT_NAME, { ...ACTIVE_SUBSCRIPTION, profile_limit: 6 });
    await page.goto('/profiles/new');
    await expect(page.getByTestId('profile-allowance')).toContainText('5 of 6 managed profiles in use.');
    await expect(page.getByTestId('profile-create-submit')).toBeEnabled();
    await page.locator('#dependent_first_name').fill('Allowance Sixth');
    await page.locator('#dependent_last_name').fill(lastName);
    await page.getByTestId('profile-create-submit').click();
    await expect(page.getByRole('heading', { name: `Allowance Sixth ${lastName}`, exact: true })).toBeVisible();
    const sixthProfileURL = page.url();

    // Synthetic renewal state: a scheduled reduction has become effective.
    setAccountSubscription(ACCOUNT_NAME, { ...ACTIVE_SUBSCRIPTION, profile_limit: 5 });
    await page.goto('/dashboard');
    await expect(page.getByTestId('profile-allowance')).toContainText('6 of 5 managed profiles in use.');
    await expect(page.getByTestId('profile-limit-reached')).toContainText("You're over your current profile allowance.");
    await expect(page.getByTestId('profile-limit-reached')).toContainText('Your existing profiles and documents stay available.');
    await expect(page.getByTestId(/^dependent-card-/)).toHaveCount(6);

    await page.goto(sixthProfileURL);
    await page.getByRole('link', { name: 'Edit', exact: true }).click();
    await expect(page.getByTestId('profile-save-submit')).toBeEnabled();
    await page.locator('#dependent_notes').fill('Still editable after the profile allowance was reduced.');
    await page.getByTestId('profile-save-submit').click();
    await expect(page.getByTestId('flash-notice')).toContainText('Profile updated.');
    await expect(page.getByText('Still editable after the profile allowance was reduced.', { exact: true })).toBeVisible();

    await page.goto('/dashboard');
    await page.getByRole('link', { name: /Emma Greenfield/ }).first().click();
    await page.getByTestId('dependent-documents-link').click();
    await expect(page).toHaveURL(/\/profiles\/\d+\/documents$/);
    await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
    await page.getByRole('link', { name: /Advance Directive/ }).click();
    await expect(page).toHaveURL(/\/documents\/\d+$/);
    const originalPath = await page.getByTestId('document-download-original').getAttribute('href');
    expect(originalPath).toMatch(/\/documents\/\d+\/original$/);
    const original = await page.request.get(originalPath);
    expect(original.ok()).toBe(true);
    expect((await original.body()).length).toBeGreaterThan(0);

    await page.goto('/profiles/new');
    await expect(page.getByTestId('profile-create-submit')).toBeDisabled();
    await expect(page.getByTestId('profile-allowance-billing-link')).toBeVisible();
  } finally {
    deleteAccountProfilesByLastName(ACCOUNT_NAME, lastName);
  }
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
