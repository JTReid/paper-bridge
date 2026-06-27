// @ts-check
import { expect } from '@playwright/test';

export const QA_USER = {
  email: 'admin@example.test',
  password: 'password',
};

export async function signIn(page) {
  await page.goto('/users/sign_in');
  await page.getByLabel('Email').fill(QA_USER.email);
  await page.getByLabel('Password').fill(QA_USER.password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByText('Your Family Hub')).toBeVisible();
  await expect(page.getByText('Emma Greenfield').first()).toBeVisible();
}

export async function openDependentWorkspace(page) {
  await signIn(page);
  await page.getByRole('link', { name: /Emma Greenfield/ }).first().click();
  await expect(page.getByRole('heading', { name: 'Emma Greenfield' })).toBeVisible();
}
