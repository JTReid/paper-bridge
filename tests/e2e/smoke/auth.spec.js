// @ts-check
import { test, expect } from '@playwright/test';
import { signIn } from '../helpers/auth';

test('fixture admin signs in to the dashboard', async ({ page }) => {
  await signIn(page);

  await expect(page.getByRole('heading', { name: 'Good to see you.' })).toBeVisible();
  await expect(page.getByText('Family Calendar')).toBeVisible();
  await expect(page.getByText('No upcoming events')).toBeVisible();
});
