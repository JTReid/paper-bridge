// @ts-check
import { randomUUID } from 'node:crypto';
import { test, expect } from '../fixtures';
import { openDependentWorkspace, signIn } from '../helpers/auth';

test('admin can create, edit, and delete a profile with separate name fields', async ({ page }) => {
  const lastName = `Morgan ${randomUUID()}`;
  await signIn(page);
  await page.goto('/profiles/new');

  await expect(page.locator('#dependent_first_name')).toBeVisible();
  await expect(page.locator('#dependent_last_name')).toBeVisible();
  await expect(page.locator('#dependent_grade')).toHaveCount(0);
  await expect(page.locator('#dependent_school')).toHaveCount(0);
  await expect(page.getByTestId('profile-delete-button')).toHaveCount(0);
  await page.locator('#dependent_first_name').fill('Jamie');
  await page.locator('#dependent_last_name').fill(lastName);
  await page.getByTestId('profile-create-submit').click();

  await expect(page.getByRole('heading', { name: `Jamie ${lastName}`, exact: true })).toBeVisible();
  await expect(page.getByTestId('flash-notice')).toContainText('Profile created.');
  const profileURL = page.url();
  await page.getByRole('link', { name: 'Edit', exact: true }).click();

  await expect(page.locator('#dependent_first_name')).toHaveValue('Jamie');
  await expect(page.locator('#dependent_last_name')).toHaveValue(lastName);
  await expect(page.locator('#dependent_grade')).toBeVisible();
  await expect(page.locator('#dependent_school')).toBeVisible();
  await page.locator('#dependent_first_name').fill('Jordan');
  await page.locator('#dependent_grade').fill('4th Grade');
  await page.locator('#dependent_school').fill('QA Profile Elementary');
  await page.getByTestId('profile-save-submit').click();

  await expect(page.getByRole('heading', { name: `Jordan ${lastName}`, exact: true })).toBeVisible();
  await expect(page.getByText('4th Grade · QA Profile Elementary', { exact: true })).toBeVisible();
  await page.getByRole('link', { name: 'Edit', exact: true }).click();

  page.once('dialog', (dialog) => dialog.dismiss());
  await page.getByTestId('profile-delete-button').click();
  await expect(page).toHaveURL(`${profileURL}/edit`);
  await page.reload();
  await expect(page.locator('#dependent_first_name')).toHaveValue('Jordan');
  await expect(page.locator('#dependent_school')).toHaveValue('QA Profile Elementary');

  page.once('dialog', (dialog) => dialog.accept());
  await page.getByTestId('profile-delete-button').click();

  await expect(page).toHaveURL(/\/profiles$/);
  await expect(page.getByTestId('flash-notice')).toContainText('Profile deleted.');
  await expect(page.getByRole('link', { name: new RegExp(lastName) })).toHaveCount(0);
});

test('admin receives instructions when a profile still has documents', async ({ page }) => {
  await openDependentWorkspace(page);
  const profileURL = page.url();
  await page.getByRole('link', { name: 'Edit', exact: true }).click();

  const documentsLink = page.getByTestId('profile-delete-documents-link');
  await expect(documentsLink).toHaveAttribute('href', `${new URL(profileURL).pathname}/documents`);
  page.once('dialog', (dialog) => dialog.accept());
  await page.getByTestId('profile-delete-button').click();

  await expect(page).toHaveURL(`${profileURL}/edit`);
  await expect(page.getByTestId('flash-alert')).toContainText('Remove this profile’s documents before deleting the profile.');
  await expect(page.locator('#dependent_first_name')).toHaveValue('Emma');
  await expect(page.locator('#dependent_last_name')).toHaveValue('Greenfield');
  await documentsLink.click();

  await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();
  await expect(page.getByTestId(/^document-row-/).first()).toBeVisible();
});
