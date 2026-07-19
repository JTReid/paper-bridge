// @ts-check
import { test, expect } from '../fixtures';
import { signIn, openDependentWorkspace } from '../helpers/auth';

test.describe('mobile product surfaces', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('public home exposes mobile entry actions', async ({ page }) => {
    await page.goto('/');

    await expect(page.getByText('PaperBridge').first()).toBeVisible();
    await page.locator('summary').first().click();
    await expect(page.getByTestId('home-mobile-secondary')).toBeVisible();
    await expect(page.getByTestId('home-mobile-primary')).toBeVisible();
  });

  test('signed-in mobile shell reaches the account calendar and billing', async ({ page }) => {
    await signIn(page);

    await expect(page.getByRole('heading', { name: 'Good to see you.' })).toBeVisible();
    await expect(page.getByTestId('desktop-sidebar')).not.toBeVisible();

    const mobileMenu = page.locator('details').first();
    await mobileMenu.locator('summary').click();
    await mobileMenu.getByRole('link', { name: 'Calendar', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Calendar', exact: true })).toBeVisible();
    await expect(page.getByTestId('calendar-grid')).toBeVisible();
    const calendarRegion = page.getByRole('region', { name: 'Monthly calendar grid' });
    await expect.poll(() => calendarRegion.evaluate((element) => element.scrollWidth > element.clientWidth)).toBe(true);
    await expect.poll(() => calendarRegion.evaluate((element) => getComputedStyle(element).scrollbarWidth)).toBe('none');

    await mobileMenu.locator('summary').click();
    await mobileMenu.getByRole('link', { name: 'Billing', exact: true }).click();
    await expect(page.getByTestId('billing-page')).toBeVisible();
    await expect(page.getByTestId('billing-status')).toContainText('Subscription active');
  });

  test('dependent mobile shell reaches documents, care team, and assistant', async ({ page }) => {
    await openDependentWorkspace(page);

    await expect(page.getByRole('heading', { name: 'Emma Greenfield' })).toBeVisible();
    await expect(page.getByTestId('desktop-sidebar')).not.toBeVisible();

    await page.locator('summary').first().click();
    await page.getByRole('link', { name: 'Documents' }).click();
    await expect(page.getByRole('heading', { name: "Emma Greenfield's Documents" })).toBeVisible();

    await page.locator('[data-testid^="document-share-button-"]').first().click();
    await expect(page.getByRole('dialog', { name: 'Share Documents' })).toBeVisible();
    await page.getByTestId('document-share-close').click();

    await page.locator('summary').first().click();
    await page.getByRole('link', { name: 'Care Team' }).click();
    await expect(page.getByRole('heading', { name: 'Care Team' })).toBeVisible();
    await page.getByTestId('care-team-invite-link').click();
    await expect(page.getByRole('heading', { name: 'Invite Care Team Member' })).toBeVisible();

    await page.locator('summary').first().click();
    await page.getByRole('link', { name: 'Ask PaperBridge' }).click();
    await expect(page.getByRole('heading', { name: 'Ask PaperBridge' })).toBeVisible();
    await expect(page.getByTestId('ai-assistant-form')).toBeVisible();
  });
});
