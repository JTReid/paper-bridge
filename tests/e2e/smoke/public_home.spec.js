// @ts-check
import { test, expect } from '../fixtures';
import { expectAccessible } from '../helpers/accessibility';

test('public home exposes entry actions', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByText('PaperBridge').first()).toBeVisible();
  await expect(page.getByTestId('home-nav-secondary')).toBeVisible();
  await expect(page.getByTestId('home-nav-primary')).toBeVisible();
  await expect(page.getByTestId('home-hero-primary')).toBeVisible();
  await expect(page.getByText('Turn overwhelming paperwork into')).toBeVisible();
  await expectAccessible(page);
});
