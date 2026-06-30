// @ts-check
import { test, expect } from '../fixtures';
import { QA_USER, signIn, openDependentWorkspace, openSeededDependentWorkspace } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';
import { setAccountSubscription } from '../helpers/backend';

const ACCOUNT_NAME = 'Greenfield Family';
const QA_SEEDED_ACCOUNT_NAME = 'PaperBridge QA Harness';
const ACTIVE_SUBSCRIPTION = {
  status: 'active',
  stripe_customer_id: 'cus_qa_accessibility',
  stripe_subscription_id: 'sub_qa_accessibility',
  stripe_price_id: 'price_qa_accessibility',
};
const SEEDED_ACTIVE_SUBSCRIPTION = {
  status: 'active',
  stripe_customer_id: 'cus_qa_seed_accessibility',
  stripe_subscription_id: 'sub_qa_seed_accessibility',
  stripe_price_id: 'price_qa_seed_accessibility',
};
const INACTIVE_SUBSCRIPTION = {
  status: 'incomplete',
  stripe_customer_id: 'cus_qa_accessibility_incomplete',
  stripe_subscription_id: null,
  stripe_price_id: 'price_qa_accessibility',
};

test.afterEach(() => {
  setAccountSubscription(ACCOUNT_NAME, ACTIVE_SUBSCRIPTION);
  setAccountSubscription(QA_SEEDED_ACCOUNT_NAME, SEEDED_ACTIVE_SUBSCRIPTION);
});

test('public and auth surfaces pass axe checks', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByText('PaperBridge').first()).toBeVisible();
  await expectAccessible(page);

  await page.goto('/users/sign_in');
  await expect(page.getByRole('heading', { name: 'Sign in', exact: true })).toBeVisible();
  await expectAccessible(page);
});

test('active product surfaces pass axe checks', async ({ page }) => {
  setAccountSubscription(ACCOUNT_NAME, ACTIVE_SUBSCRIPTION);

  await signIn(page);
  await expect(page.getByRole('heading', { name: 'Good to see you.' })).toBeVisible();
  await expectAccessible(page);

  await page.getByRole('link', { name: /Emma Greenfield/ }).first().click();
  await expect(page.getByRole('heading', { name: 'Emma Greenfield' })).toBeVisible();
  await expectAccessible(page);

  await page.getByTestId('dependent-documents-link').click();
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await expectAccessible(page);

  await page.locator('[data-testid^="document-share-button-"]').first().click();
  await expect(page.getByRole('dialog', { name: 'Share Documents' })).toBeVisible();
  await expectAccessible(page, { include: ['[data-testid="document-share-dialog"]'] });

  await page.getByTestId('document-share-close').click();
  await page.getByTestId('documents-add-link').click();
  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await expectAccessible(page);
});

test('care team and AI surfaces pass axe checks', async ({ page }) => {
  setAccountSubscription(ACCOUNT_NAME, ACTIVE_SUBSCRIPTION);

  await openDependentWorkspace(page);
  await page.getByTestId('dependent-care-team-link').click();
  await expect(page.getByRole('heading', { name: 'Care Team' })).toBeVisible();
  await expectAccessible(page);

  await page.getByTestId('care-team-invite-link').click();
  await expect(page.getByRole('heading', { name: 'Invite Care Team Member' })).toBeVisible();
  await expectAccessible(page);

  await page.goto('/dashboard');
  await page.getByRole('link', { name: /Emma Greenfield/ }).first().click();
  await expect(page.getByRole('heading', { name: 'Emma Greenfield' })).toBeVisible();
  await page.getByTestId('dependent-ai-assistant-link').click();
  await expect(page.getByRole('heading', { name: 'AI Assistant' })).toBeVisible();
  await expectAccessible(page);
});

test('billing gate passes axe checks', async ({ page }) => {
  setAccountSubscription(ACCOUNT_NAME, INACTIVE_SUBSCRIPTION);

  await signInWithoutDashboardExpectation(page);
  await expect(page).toHaveURL(/\/billing$/);
  await expect(page.getByTestId('billing-status')).toContainText('Subscription required');
  await expectAccessible(page);
});

test('seeded document edge states pass axe checks', async ({ page }) => {
  setAccountSubscription(ACCOUNT_NAME, ACTIVE_SUBSCRIPTION);
  setAccountSubscription(QA_SEEDED_ACCOUNT_NAME, SEEDED_ACTIVE_SUBSCRIPTION);

  await openSeededDependentWorkspace(page);
  await page.getByTestId('dependent-documents-link').click();
  await expect(page.getByRole('heading', { name: "Avery Morgan's Documents" })).toBeVisible();
  await expectAccessible(page);

  await page.getByRole('link', { name: /QA Edge Preparation Failed/ }).click();
  await expect(page.getByRole('heading', { name: 'QA Edge Preparation Failed' })).toBeVisible();
  await expectAccessible(page);
});

async function signInWithoutDashboardExpectation(page) {
  await page.goto('/users/sign_in');
  await page.getByTestId('sign-in-email').fill(QA_USER.email);
  await page.getByTestId('sign-in-password').fill(QA_USER.password);
  await page.getByTestId('sign-in-submit').click();
}
