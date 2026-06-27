// @ts-check
import { test, expect } from '@playwright/test';

test('public home exposes entry actions', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByText('PaperBridge').first()).toBeVisible();
  await expect(page.getByRole('link', { name: 'Sign In' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Get Started' }).first()).toBeVisible();
  await expect(page.getByText('Turn overwhelming paperwork into')).toBeVisible();
});
