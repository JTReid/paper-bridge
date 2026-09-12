// @ts-check
import { test, expect } from '../fixtures';
import { expectAccessible } from '../helpers/accessibility';
import { replaceNativeYear } from '../helpers/date_input';

const APPOINTMENT = {
  date: '2031-05-14',
  localDateTime: '2031-05-14T10:30',
  description: '{"office":"west"}',
  dependent: 'Emma Greenfield',
};
const RECIPIENT_EMAIL = 'caregiver@example.test';

test('family calendar panel preserves unfinished profile work', async ({ page, family }) => {
  await family.openDependentWorkspace(page);
  await page.getByRole('link', { name: 'Edit', exact: true }).click();

  const notes = page.getByLabel('Notes');
  const unfinishedNotes = `Unsaved family calendar note ${Date.now()}`;
  await notes.fill(unfinishedNotes);
  const editURL = page.url();
  const calendarTrigger = page.getByTestId('nav-calendar');

  await calendarTrigger.click();

  const familyCalendar = page.getByTestId('family-calendar-dialog');
  await expect(familyCalendar).toBeVisible();
  await expect(familyCalendar.getByRole('heading', { name: 'Family Calendar', exact: true })).toBeVisible();
  await expect(page).toHaveURL(editURL);
  await expect(page.getByTestId('family-calendar-close')).toBeFocused();

  const frame = page.getByTestId('family-calendar-frame');
  await expect(frame.getByTestId('family-calendar-content')).toBeVisible();
  await expect(frame.getByTestId('appointment-dependent').locator('option:checked')).toHaveText('Emma Greenfield');

  await frame.getByTestId('calendar-next-month').click();
  await expect(page).toHaveURL(editURL);
  const monthHeading = frame.getByRole('heading', { name: /.+ \d{4}/ });
  await expect(monthHeading).toBeVisible();
  await expect(monthHeading).toBeFocused();

  const emmaAppointment = frame.locator('button[data-testid^="appointment-"]', { hasText: 'Speech therapy appointment' });
  const noahAppointment = frame.locator('button[data-testid^="appointment-"]', { hasText: 'Dental checkup' });
  await expect(emmaAppointment).toContainText('Emma Greenfield');
  await expect(noahAppointment).toContainText('Noah Greenfield');

  await frame.getByTestId('appointment-dependent').selectOption({ label: 'Noah Greenfield' });

  const description = `Profile calendar appointment ${Date.now()}`;
  await frame.getByTestId('appointment-description').fill(description);
  await frame.getByTestId('appointment-submit').click();

  await expect(familyCalendar).toBeVisible();
  await expect(page).toHaveURL(editURL);
  await expect(frame.getByTestId('family-calendar-notice')).toContainText('Appointment added');
  await expect(frame.getByTestId('family-calendar-notice')).toBeFocused();

  const createdAppointment = frame.locator('button[data-testid^="appointment-"]', { hasText: description });
  await expect(createdAppointment).toContainText('Noah Greenfield');
  await expect(frame.getByTestId('appointment-dependent').locator('option:checked')).toHaveText('Emma Greenfield');
  await createdAppointment.click();

  const appointmentDetails = frame.getByTestId('appointment-dialog');
  await expect(appointmentDetails).toBeVisible();
  await appointmentDetails.getByLabel('Email to').fill(RECIPIENT_EMAIL);
  await appointmentDetails.getByTestId('appointment-email-submit').click();

  await expect(familyCalendar).toBeVisible();
  await expect(page).toHaveURL(editURL);
  await expect(frame.getByTestId('family-calendar-notice')).toContainText(`Appointment emailed to ${RECIPIENT_EMAIL}`);
  await expect(frame.getByTestId('family-calendar-notice')).toBeFocused();

  await page.getByTestId('family-calendar-close').click();

  await expect(familyCalendar).toBeHidden();
  await expect(page).toHaveURL(editURL);
  await expect(notes).toHaveValue(unfinishedNotes);
  await expect(calendarTrigger).toBeFocused();
});

test('family admin can add, review, and email a profile appointment on the account calendar', async ({ page, family }) => {
  await family.signIn(page);

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
  const scheduledAt = page.getByTestId('appointment-scheduled-at');
  await scheduledAt.fill('2000-05-14T10:30');
  await replaceNativeYear(page, scheduledAt, '2031');
  await expect(scheduledAt).toHaveValue(APPOINTMENT.localDateTime);
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
  await expect(details.locator('[data-appointment-dialog-target="dependent"]')).toHaveText(APPOINTMENT.dependent);
  await expect(details.locator('[data-appointment-dialog-target="description"]')).toHaveText(APPOINTMENT.description);
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

test('appointment edits can be canceled, corrected after validation, and saved to another profile and month', async ({ page, family }) => {
  const description = `Appointment edit ${Date.now()}`;
  const updatedDescription = `${description} updated`;
  const originalDateTime = '2034-05-16T09:15';
  const updatedDateTime = '2035-06-17T14:45';
  await family.signIn(page);
  await page.goto('/calendar?month=2034-05');
  await page.getByTestId('appointment-dependent').selectOption({ label: 'Emma Greenfield' });
  await page.getByTestId('appointment-scheduled-at').fill(originalDateTime);
  await page.getByTestId('appointment-description').fill(description);
  await page.getByTestId('appointment-submit').click();
  await expect(page.getByTestId('flash-notice')).toContainText('Appointment added');

  const appointment = page.getByTestId('calendar-grid').getByRole('button', { name: new RegExp(description) });
  const appointmentId = (await appointment.getAttribute('data-testid')).replace('appointment-', '');
  await appointment.click();
  const details = page.getByTestId('appointment-dialog');
  const editForm = details.getByTestId('appointment-edit-form');
  const editDependent = details.getByTestId('appointment-edit-dependent');
  const editDateTime = details.getByTestId('appointment-edit-scheduled-at');
  const editDescription = details.getByTestId('appointment-edit-description');

  await details.getByTestId('appointment-edit-button').click();
  await expect(editForm).toBeVisible();
  await expect(editDependent.locator('option:checked')).toHaveText('Emma Greenfield');
  await expect(editDateTime).toHaveValue(originalDateTime);
  await expect(editDescription).toHaveValue(description);
  await editDependent.selectOption({ label: 'Noah Greenfield' });
  await editDateTime.fill(updatedDateTime);
  await editDescription.fill('Unsaved replacement');
  await details.getByTestId('appointment-edit-cancel').click();
  await expect(editForm).toBeHidden();
  await expect(details.locator('[data-appointment-dialog-target="description"]')).toBeVisible();
  await expect(details.locator('[data-appointment-dialog-target="description"]')).toHaveText(description);
  await expect(details.locator('[data-appointment-dialog-target="dependent"]')).toHaveText('Emma Greenfield');

  await details.getByTestId('appointment-edit-button').click();
  await expect(editDependent.locator('option:checked')).toHaveText('Emma Greenfield');
  await expect(editDateTime).toHaveValue(originalDateTime);
  await expect(editDescription).toHaveValue(description);
  await editDependent.selectOption({ label: 'Noah Greenfield' });
  await editDateTime.fill('2034-06-17T14:45');
  await replaceNativeYear(page, editDateTime, '2035');
  await expect(editDateTime).toHaveValue(updatedDateTime);
  // Whitespace passes HTML required checks and exercises actual Rails validation.
  await editDescription.fill('   ');
  const invalidResponse = page.waitForResponse((response) =>
    new URL(response.url()).pathname === `/appointments/${appointmentId}` && response.status() === 422,
  );
  await details.getByTestId('appointment-edit-submit').click();
  await invalidResponse;
  await expect(details).toBeVisible();
  await expect(editForm).toBeVisible();
  await expect(details.getByTestId('appointment-edit-errors')).toContainText("Description can't be blank");
  await expect(editDependent.locator('option:checked')).toHaveText('Noah Greenfield');
  await expect(editDateTime).toHaveValue(updatedDateTime);
  await expect(page.getByTestId('appointment-description')).toHaveValue('');
  await expect(page.getByTestId('appointment-form').locator('input[name="_method"]')).toHaveCount(0);
  await expectAccessible(page, { include: ['[data-testid="appointment-dialog"]'] });

  await details.getByTestId('appointment-edit-cancel').click();
  await expect(editForm).toBeHidden();
  await expect(details.locator('[data-appointment-dialog-target="description"]')).toBeVisible();
  await expect(details.locator('[data-appointment-dialog-target="description"]')).toHaveText(description);
  await expect(details.locator('[data-appointment-dialog-target="dependent"]')).toHaveText('Emma Greenfield');
  await details.getByTestId('appointment-edit-button').click();
  await expect(editDescription).toHaveValue(description);
  await expect(editDateTime).toHaveValue(originalDateTime);
  await editDependent.selectOption({ label: 'Noah Greenfield' });
  await editDateTime.fill(updatedDateTime);
  await editDescription.fill(updatedDescription);
  await details.getByTestId('appointment-edit-submit').click();

  await expect(page).toHaveURL(/\/calendar\?month=2035-06$/);
  await expect(page.getByTestId('flash-notice')).toContainText('Appointment updated');
  await expect(details).toBeHidden();
  await expect(page.getByTestId('appointment-description')).toHaveValue('');
  await expect(page.getByTestId('appointment-form').locator('input[name="_method"]')).toHaveCount(0);
  await page.reload();
  const updatedAppointment = page.getByTestId(`appointment-${appointmentId}`);
  await expect(updatedAppointment).toContainText(updatedDescription);
  await expect(updatedAppointment).toContainText('Noah Greenfield');
  await expect(page.locator('[data-calendar-date="2035-06-17"]').getByTestId(`appointment-${appointmentId}`)).toBeVisible();
  await updatedAppointment.click();
  await details.getByTestId('appointment-edit-button').click();
  await expect(editDateTime).toHaveValue(updatedDateTime);
  await expect(editDescription).toHaveValue(updatedDescription);
  await details.getByTestId('appointment-edit-cancel').click();
  page.once('dialog', (dialog) => dialog.accept());
  await details.getByTestId('appointment-delete-button').click();
  await expect(page).toHaveURL(/\/calendar\?month=2035-06$/);
  await expect(page.getByTestId('flash-notice')).toContainText('Appointment deleted');
  await expect(updatedAppointment).toHaveCount(0);
});

test('phone calendar edits and confirmed deletion preserve an unfinished Ask question', async ({ page, family }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await family.openDependentWorkspace(page);
  await page.goto(`${page.url()}/ai-assistant`);
  const askURL = page.url();
  const question = 'What should I bring to the upcoming meeting?';
  const questionInput = page.getByTestId('ai-assistant-query');
  await questionInput.fill(question);
  await page.locator('details').first().locator('summary').click();
  const calendarTrigger = page.getByTestId('mobile-nav-calendar');
  await calendarTrigger.click();

  const familyCalendar = page.getByTestId('family-calendar-dialog');
  const frame = familyCalendar.getByTestId('family-calendar-frame');
  await expect(frame.getByTestId('calendar-agenda')).toBeVisible();
  const description = `Phone appointment ${Date.now()}`;
  const updatedDescription = `${description} updated`;
  await frame.getByTestId('appointment-description').fill(description);
  await frame.getByTestId('appointment-scheduled-at').fill('2036-09-11T11:00');
  await frame.getByTestId('appointment-submit').click();
  await expect(frame.getByTestId('family-calendar-notice')).toContainText('Appointment added');
  await expect(page).toHaveURL(askURL);
  const agendaAppointment = frame.getByTestId('calendar-agenda').getByRole('button', { name: new RegExp(description) });
  const appointmentId = (await agendaAppointment.getAttribute('data-testid')).replace('agenda-appointment-', '');
  await agendaAppointment.click();
  const details = frame.getByTestId('appointment-dialog');
  await details.getByTestId('appointment-edit-button').click();
  await expect(details.getByTestId('appointment-edit-form')).toBeVisible();
  await expect.poll(() => details.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);
  await expectAccessible(page, { include: ['[data-testid="appointment-dialog"]'] });
  await details.getByTestId('appointment-edit-dependent').selectOption({ label: 'Noah Greenfield' });
  await details.getByTestId('appointment-edit-description').fill('   ');
  await details.getByTestId('appointment-edit-scheduled-at').fill('2036-09-12T12:15');
  const invalidResponse = page.waitForResponse((response) =>
    new URL(response.url()).pathname === `/appointments/${appointmentId}` && response.status() === 422,
  );
  await details.getByTestId('appointment-edit-submit').click();
  await invalidResponse;
  await expect(familyCalendar).toBeVisible();
  await expect(details).toBeVisible();
  await expect(details.getByTestId('appointment-edit-form')).toBeVisible();
  await expect(details.getByTestId('appointment-edit-errors')).toContainText("Description can't be blank");
  await expect(details.getByTestId('appointment-edit-errors')).toBeFocused();
  await expect(details.getByTestId('appointment-edit-dependent').locator('option:checked')).toHaveText('Noah Greenfield');
  await expect(details.getByTestId('appointment-edit-scheduled-at')).toHaveValue('2036-09-12T12:15');
  await expect(frame.getByTestId('appointment-description')).toHaveValue('');
  await expect(page).toHaveURL(askURL);
  await details.getByTestId('appointment-edit-description').fill(updatedDescription);
  await details.getByTestId('appointment-edit-submit').click();
  await expect(frame.getByTestId('family-calendar-notice')).toContainText('Appointment updated');
  await expect(familyCalendar).toBeVisible();
  await expect(details).toBeHidden();
  await expect(page).toHaveURL(askURL);
  await expect(frame.getByTestId('appointment-description')).toHaveValue('');

  const updatedAppointment = frame.getByTestId(`agenda-appointment-${appointmentId}`);
  await expect(updatedAppointment).toContainText(updatedDescription);
  await expect(updatedAppointment).toContainText('Noah Greenfield');
  const countBeforeDeletion = await monthlyAppointmentCount(frame);
  await updatedAppointment.click();
  page.once('dialog', (dialog) => dialog.dismiss());
  await details.getByTestId('appointment-delete-button').click();
  await expect(details).toBeVisible();
  await expect(updatedAppointment).toHaveCount(1);
  expect(await monthlyAppointmentCount(frame)).toBe(countBeforeDeletion);
  page.once('dialog', (dialog) => dialog.accept());
  await details.getByTestId('appointment-delete-button').click();

  await expect(frame.getByTestId('family-calendar-notice')).toContainText('Appointment deleted');
  await expect(familyCalendar).toBeVisible();
  await expect(details).toBeHidden();
  await expect(page).toHaveURL(askURL);
  await expect(frame.locator('#calendar-month-heading')).toHaveText('September 2036');
  await expect(updatedAppointment).toHaveCount(0);
  await expect(frame.getByTestId(`appointment-${appointmentId}`)).toHaveCount(0);
  await expect.poll(() => monthlyAppointmentCount(frame)).toBe(countBeforeDeletion - 1);
  await page.getByTestId('family-calendar-close').click();
  await expect(familyCalendar).toBeHidden();
  await expect(page).toHaveURL(askURL);
  await expect(questionInput).toHaveValue(question);
  await expect(calendarTrigger).toBeFocused();
});

async function monthlyAppointmentCount(scope) {
  const text = await scope.getByText(/^\d+ appointments? this month$/).innerText();
  return Number(text.split(' ')[0]);
}
