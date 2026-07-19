// @ts-check
import { test, expect } from '../fixtures';
import { signIn } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';

const APPOINTMENT = {
  date: '2031-05-14',
  localDateTime: '2031-05-14T10:30',
  description: '{"office":"west"}',
  dependent: 'Emma Greenfield',
};
const RECIPIENT_EMAIL = 'caregiver@example.test';

test('family admin can add, review, and email a profile appointment on the account calendar', async ({ page }) => {
  await signIn(page);

  await expect(page.getByTestId('dashboard-calendar-link')).toHaveAttribute('href', '/calendar');
  await page.getByTestId('dashboard-calendar-link').click();

  await expect(page).toHaveURL(/\/calendar$/);
  await expect(page.getByTestId('calendar-page')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Calendar', exact: true })).toBeVisible();
  await expect(page.getByTestId('calendar-grid')).toBeVisible();
  const calendarRegion = page.getByRole('region', { name: 'Monthly calendar grid' });
  await expect.poll(() => calendarRegion.evaluate((element) => element.scrollWidth - element.clientWidth)).toBe(0);
  await expect.poll(() => calendarRegion.evaluate((element) => getComputedStyle(element).scrollbarWidth)).toBe('none');
  await expectAccessible(page);

  await page.getByTestId('appointment-dependent').selectOption({ label: APPOINTMENT.dependent });
  await page.getByTestId('appointment-scheduled-at').fill(APPOINTMENT.localDateTime);
  await page.getByTestId('appointment-description').fill(APPOINTMENT.description);
  await page.getByTestId('appointment-submit').click();

  await expect(page).toHaveURL(/\/calendar\?month=2031-05$/);
  await expect(page.getByTestId('flash-notice')).toContainText('Appointment added');
  await expect(page.getByRole('heading', { name: 'May 2031', exact: true })).toBeVisible();

  const appointmentDay = page.locator(`[data-calendar-date="${APPOINTMENT.date}"]`);
  await expect(appointmentDay.locator('time')).toHaveAttribute('datetime', APPOINTMENT.date);

  const appointmentButton = appointmentDay.locator('button[data-testid^="appointment-"]', { hasText: APPOINTMENT.description });
  await expect(appointmentButton).toContainText('10:30 AM');
  await expect(appointmentButton).toContainText(APPOINTMENT.dependent);
  await appointmentButton.click();

  const details = page.getByTestId('appointment-dialog');
  await expect(details).toBeVisible();
  await expect.poll(() => details.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    return Math.abs(bounds.left + (bounds.width / 2) - (window.innerWidth / 2));
  })).toBeLessThan(2);
  await expect.poll(() => details.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    return Math.abs(bounds.top + (bounds.height / 2) - (window.innerHeight / 2));
  })).toBeLessThan(2);
  await expect(details.getByText('Appointment Details')).toBeVisible();
  await expect(details.getByText('Wednesday, May 14, 2031 at 10:30 AM CDT')).toBeVisible();
  await expect(details.getByText(APPOINTMENT.dependent, { exact: true })).toBeVisible();
  await expect(details.getByText(APPOINTMENT.description, { exact: true })).toBeVisible();
  const appointmentId = (await appointmentButton.getAttribute('data-testid'))?.replace('appointment-', '') || '';
  expect(appointmentId).not.toBe('');
  await expect(details.getByTestId('appointment-email-form')).toBeVisible();
  await expect(details.getByTestId('appointment-email-appointment-id')).toHaveValue(appointmentId);
  const recipientInput = details.getByLabel('Email to');
  await expect(recipientInput).toHaveAttribute('type', 'email');
  expect(await recipientInput.evaluate((input) => input.required)).toBe(true);
  const sendButton = details.getByRole('button', { name: 'Send', exact: true });
  await expect(sendButton).toBeVisible();
  await expectAccessible(page, { include: ['[data-testid="appointment-dialog"]'] });

  await sendButton.focus();
  await page.keyboard.press('Enter');
  await expect(details).toBeVisible();
  await expect(recipientInput).toBeFocused();
  expect(await recipientInput.evaluate((input) => input.validity.valueMissing)).toBe(true);

  await details.getByRole('button', { name: 'Close appointment details' }).click();
  await expect(details).toBeHidden();
  await appointmentButton.click();
  await expect(details).toBeVisible();

  await recipientInput.fill(RECIPIENT_EMAIL);
  await details.getByTestId('appointment-email-submit').click();

  await expect(page).toHaveURL(/\/calendar\?month=2031-05$/);
  await expect(page.getByTestId('flash-notice')).toContainText(`Appointment emailed to ${RECIPIENT_EMAIL}`);

  await page.getByTestId('calendar-next-month').click();
  await expect(page).toHaveURL(/\/calendar\?month=2031-06$/);
  await expect(page.getByRole('heading', { name: 'June 2031', exact: true })).toBeVisible();
  await expect(page.locator('button[data-testid^="appointment-"]', { hasText: APPOINTMENT.description })).toHaveCount(0);

  await page.getByTestId('calendar-previous-month').click();
  await expect(page).toHaveURL(/\/calendar\?month=2031-05$/);
  await expect(page.getByRole('heading', { name: 'May 2031', exact: true })).toBeVisible();
  await expect(page.locator('button[data-testid^="appointment-"]', { hasText: APPOINTMENT.description })).toBeVisible();
});
