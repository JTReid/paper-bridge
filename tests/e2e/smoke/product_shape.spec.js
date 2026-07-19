// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace, signIn } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';

test('active account can reach the current product surface', async ({ page }) => {
  await signIn(page);

  await expect(page.getByRole('heading', { name: 'Good to see you.' })).toBeVisible();
  await expect(page.getByTestId('nav-dashboard')).toBeVisible();
  await expect(page.getByTestId('nav-dependents')).toBeVisible();
  await expect(page.getByTestId('nav-calendar')).toBeVisible();
  await expect(page.getByTestId('nav-billing')).toBeVisible();

  await page.goto('/billing');
  await expect(page.getByTestId('billing-page')).toBeVisible();
  await expect(page.getByTestId('billing-status')).toContainText('Subscription active');
  await expectAccessible(page);
});

test('dependent workspace exposes implemented child workflows', async ({ page }) => {
  await openDependentWorkspace(page);

  await expect(page.getByRole('heading', { name: 'Emma Greenfield' })).toBeVisible();
  await expect(page.getByTestId('dependent-documents-link')).toBeVisible();
  await expect(page.getByTestId('dependent-care-team-link')).toBeVisible();
  await expect(page.getByTestId('dependent-ai-assistant-link')).toBeVisible();
  await expectAccessible(page);

  await page.getByTestId('dependent-documents-link').click();
  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await expect(page.getByTestId('documents-add-link')).toBeVisible();
  await expect(page.getByTestId('documents-ask-ai-link')).toBeVisible();
  await expect(page.locator('[data-testid^="document-row-"]').first()).toBeVisible();

  await page.locator('[data-testid^="document-share-button-"]').first().click();
  await expect(page.getByRole('dialog', { name: 'Share Documents' })).toBeVisible();
  await page.getByTestId('document-share-recipient-select').selectOption('therapist@example.test');
  await expect(page.getByTestId('document-share-recipient-email')).toHaveValue('therapist@example.test');
  await page.getByTestId('document-share-close').click();

  await page.getByTestId('documents-add-link').click();
  await expect(page.getByRole('heading', { name: 'Upload Document' })).toBeVisible();
  await expect(page.getByTestId('document-upload-form')).toBeVisible();
  await page.goBack();

  await page.locator('[data-testid^="document-row-"]').first().getByRole('link').click();
  await expect(page).toHaveURL(/\/documents\/\d+$/);
  await expect(page.getByTestId('document-edit-link')).toBeVisible();
});

test('care team and ai assistant surfaces render without submitting workflows', async ({ page }) => {
  await openDependentWorkspace(page);
  const aiAssistantPath = await page.getByTestId('dependent-ai-assistant-link').getAttribute('href');

  await page.getByTestId('dependent-care-team-link').click();
  await expect(page.getByRole('heading', { name: 'Care Team' })).toBeVisible();
  await expect(page.getByText('Therapist User')).toBeVisible();
  await expect(page.getByTestId('care-team-invite-link')).toBeVisible();

  await page.getByTestId('care-team-invite-link').click();
  await expect(page.getByRole('heading', { name: 'Invite Care Team Member' })).toBeVisible();
  await expect(page.getByTestId('care-team-form')).toBeVisible();

  await page.goto(aiAssistantPath || '/dashboard');
  await expect(page.getByRole('heading', { name: 'Ask PaperBridge' })).toBeVisible();
  await expect(page.getByTestId('ai-assistant-form')).toBeVisible();
  await expect(page.getByText('Suggested questions')).toBeVisible();
  await expectAccessible(page);
});
