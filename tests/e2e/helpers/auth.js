// @ts-check
import { expect } from '@playwright/test';

export const QA_USER = {
  email: 'admin@example.test',
  password: 'password',
};

export const QA_SEEDED_USER = {
  email: 'qa-family-admin@example.test',
  password: 'password',
};

export async function signIn(page, { user = QA_USER, dependentName = 'Emma Greenfield' } = {}) {
  await page.goto('/users/sign_in');
  await page.getByTestId('sign-in-email').fill(user.email);
  await page.getByTestId('sign-in-password').fill(user.password);
  await page.getByTestId('sign-in-submit').click();
  await expect(page.getByText('Your Family Hub')).toBeVisible();
  await expect(page.getByText(dependentName).first()).toBeVisible();
}

export async function openDependentWorkspace(page) {
  await signIn(page);
  await page.getByRole('link', { name: /Emma Greenfield/ }).first().click();
  await expect(page.getByRole('heading', { name: 'Emma Greenfield' })).toBeVisible();
}

export async function openSeededDependentWorkspace(page) {
  await signIn(page, { user: QA_SEEDED_USER, dependentName: 'Avery Morgan' });
  await page.getByRole('link', { name: /Avery Morgan/ }).first().click();
  await expect(page.getByRole('heading', { name: 'Avery Morgan' })).toBeVisible();
}
