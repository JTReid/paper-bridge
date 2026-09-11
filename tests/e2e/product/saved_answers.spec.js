// @ts-check
import { test, expect } from '../fixtures';
import { signIn } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';
import {
  createSavedResearchScenario,
  deleteSavedResearchScenario,
  removeSavedResearchSource,
} from '../helpers/backend';

let research;

test.beforeEach(() => {
  research = createSavedResearchScenario();
});

test.afterEach(() => {
  if (research) deleteSavedResearchScenario(research.profileId);
  research = undefined;
});

const answerCards = (page) => page.getByTestId(/^saved-answer-\d+$/);
const meetingRows = (page) => page.getByTestId(/^meeting-prep-answer-\d+$/);
const answerChoices = (page) => page.getByTestId(/^meeting-prep-answer-choice-\d+$/);
const answerChoice = (page, answer) => page.getByTestId(`meeting-prep-answer-choice-${answer.id}`);

async function submitBatch(page, meetingId = research.emptyMeetingId) {
  const [response] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === 'POST'
      && new URL(response.url()).pathname === `/profiles/${research.profileId}/meeting-prep/${meetingId}/answers`),
    page.getByTestId('meeting-prep-add-answer').click(),
  ]);
  expect(response.status()).toBe(200);
  expect(response.headers()['content-type']).toContain('text/vnd.turbo-stream.html');
}

async function expectScrollPreserved(page) {
  await expect.poll(() => page.evaluate(() => Math.abs(window.scrollY - Number(document.body.dataset.meetingSubmitScrollY)))).toBeLessThanOrEqual(2);
}

async function openResearch(page, suffix = 'saved-answers') {
  await signIn(page);
  await page.goto(`/profiles/${research.profileId}/${suffix}`);
}

async function searchLibrary(page, query) {
  await page.getByTestId('saved-answers-search').fill(query);
  const [response] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === 'GET'
      && new URL(response.url()).pathname === `/profiles/${research.profileId}/saved-answers`
      && new URL(response.url()).searchParams.get('q') === query),
    page.getByTestId('saved-answers-search').press('Enter'),
  ]);
  await response.finished();
  await expect(page).toHaveURL((url) => url.searchParams.get('q') === query);
}

test('a completed answer can be saved, annotated, and recalled after asking another question', async ({ page }) => {
  await openResearch(page, 'ai-assistant');
  await expect(page.getByText('Start with visual supports and a calm arrival routine.')).toBeVisible();
  await page.getByTestId('ai-assistant-save-answer').click();
  await expect(page).toHaveURL(new RegExp(`/profiles/${research.profileId}/saved-answers/\\d+$`));
  const savedPath = new URL(page.url()).pathname;

  await expect(page.getByRole('heading', { name: 'Which support should we discuss next?', exact: true })).toBeVisible();
  await expect(page.getByText('Discuss these suggestions with the care team.')).toBeVisible();
  const dates = await page.locator('time').evaluateAll((elements) => elements.map((element) => Date.parse(element.getAttribute('datetime'))));
  expect(dates).toContain(Date.parse('2026-09-02T10:00:00Z'));
  expect(new Set(dates).size).toBeGreaterThan(1);
  const sourceLink = page.getByRole('link', { name: /Open source 1: Occupational evaluation/ }).first();
  await expect(sourceLink).toHaveAttribute('href', `/documents/${research.sourceId}`);
  const [sourcePage] = await Promise.all([page.waitForEvent('popup'), sourceLink.click()]);
  await expect(sourcePage.getByRole('heading', { name: 'Occupational evaluation', exact: true })).toBeVisible();
  await sourcePage.close();

  await page.getByTestId('saved-answer-edit').click();
  await page.getByTestId('saved-answer-title-field').fill('Arrival routine for the school meeting');
  await page.getByTestId('saved-answer-notes-field').fill('Ask the teacher about a quiet entrance.');
  await page.getByTestId('saved-answer-submit').click();
  await expect(page.getByRole('heading', { name: 'Arrival routine for the school meeting', exact: true })).toBeVisible();
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Arrival routine for the school meeting', exact: true })).toBeVisible();
  await expect(page.getByText('Ask the teacher about a quiet entrance.')).toBeVisible();
  await expect(page.getByText('Which support should we discuss next?', { exact: true })).toBeVisible();

  await page.getByTestId('research-nav-ask').click();
  await page.getByTestId('ai-assistant-query').fill('What should we ask about the lunch break?');
  const started = page.waitForResponse((response) => response.request().method() === 'POST'
    && /\/ai-assistant\/\d+\/start$/.test(response.url()));
  await page.getByTestId('ai-assistant-submit').click();
  expect((await started).status()).toBe(202);
  await expect(page.getByTestId('ai-assistant-query-result')).toHaveAttribute('data-phase', 'queued');
  await page.getByTestId('research-nav-saved-answers').click();
  await expect(answerCards(page)).toHaveCount(31);
  await page.getByRole('link', { name: 'Arrival routine for the school meeting', exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`${savedPath}$`));
  await expect(page.getByText('Start with visual supports and a calm arrival routine.')).toBeVisible();
  await expect(page.getByText('Ask the teacher about a quiet entrance.')).toBeVisible();
  await expectAccessible(page);
});

test('the saved library searches every research field using literal case-insensitive text', async ({ page }) => {
  await openResearch(page);
  await expect(answerCards(page)).toHaveCount(30);
  const unexpectedAiRequests = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' && request.url().includes('/ai-assistant')) unexpectedAiRequests.push(request.url());
  });

  for (const query of ['SENSORY', 'vestibular', 'WEIGHTED BLANKET', 'hallway', 'OCCUPATIONAL EVALUATION']) {
    await searchLibrary(page, query);
    await expect(answerCards(page)).toHaveCount(1);
    await expect(page.getByTestId(`saved-answer-${research.answers[0].id}`)).toBeVisible();
  }

  await searchLibrary(page, '%');
  await expect(answerCards(page)).toHaveCount(1);
  await expect(page.getByTestId(`saved-answer-${research.answers[1].id}`)).toBeVisible();
  await searchLibrary(page, '_');
  await expect(answerCards(page)).toHaveCount(1);
  await expect(page.getByTestId(`saved-answer-${research.answers[2].id}`)).toBeVisible();
  await searchLibrary(page, 'nothing-matches-this-research');
  await expect(answerCards(page)).toHaveCount(0);
  await searchLibrary(page, '');
  await expect(answerCards(page)).toHaveCount(30);
  expect(unexpectedAiRequests).toEqual([]);
});

test('meeting answers can be reordered, reused, and removed without deleting saved research', async ({ page }) => {
  await openResearch(page, `meeting-prep/${research.meetingId}`);
  const first = research.answers[0];
  const second = research.answers[1];
  await expect(meetingRows(page)).toHaveCount(30);
  await page.getByTestId(`meeting-prep-answer-${first.entryId}`).getByTestId('meeting-prep-answer-down').click();
  await expect(meetingRows(page).first()).toHaveAttribute('data-testid', `meeting-prep-answer-${second.entryId}`);
  await page.reload();
  await expect(meetingRows(page).nth(1)).toHaveAttribute('data-testid', `meeting-prep-answer-${first.entryId}`);
  await page.getByTestId(`meeting-prep-answer-${first.entryId}`).getByTestId('meeting-prep-answer-remove').click();
  await expect(meetingRows(page)).toHaveCount(29);

  await page.getByTestId('research-nav-saved-answers').click();
  await page.getByTestId('saved-answers-meeting-filter').selectOption(String(research.meetingId));
  await page.getByRole('button', { name: 'Search', exact: true }).click();
  await expect(answerCards(page)).toHaveCount(29);
  await expect(page.getByTestId(`saved-answer-${first.id}`)).toHaveCount(0);
  await page.goto(`/profiles/${research.profileId}/saved-answers/${first.id}`);
  await page.getByTestId('saved-answer-meeting-select').selectOption(String(research.meetingId));
  await page.getByTestId('saved-answer-add-to-meeting').click();
  await expect(meetingRows(page)).toHaveCount(30);
  await expect(meetingRows(page).last()).toContainText(first.title);

  await page.getByTestId('research-nav-meeting-prep').click();
  await page.getByTestId('meeting-prep-new-link').click();
  await page.getByTestId('meeting-prep-name-field').fill('Therapy follow-up');
  await page.getByTestId('meeting-prep-submit').click();
  await expect(page.getByRole('heading', { name: 'Therapy follow-up', exact: true })).toBeVisible();
  await answerChoice(page, first).check();
  await page.getByTestId('meeting-prep-add-answer').click();
  await expect(meetingRows(page)).toHaveCount(1);
  await expect(meetingRows(page).first()).toContainText(first.title);
  page.once('dialog', (dialog) => dialog.accept());
  await page.getByTestId('meeting-prep-delete').click();
  await expect(page.getByRole('heading', { name: 'Meeting prep', exact: true })).toBeVisible();

  await page.getByTestId('research-nav-saved-answers').click();
  await expect(answerCards(page)).toHaveCount(30);
  await expect(page.getByTestId(`saved-answer-${first.id}`)).toBeVisible();
  await page.goto(`/profiles/${research.profileId}/meeting-prep/${research.meetingId}`);
  await expect(meetingRows(page)).toHaveCount(30);
  await expect(meetingRows(page).last()).toContainText(first.title);
});

test('the batch picker keeps selections across searches and adds exactly the selected answers in one request', async ({ page }) => {
  await openResearch(page, `meeting-prep/${research.emptyMeetingId}`);
  const [first, second, third] = research.answers;
  const search = page.getByTestId('meeting-prep-picker-search');
  const submit = page.getByTestId('meeting-prep-add-answer');
  await expect(answerChoices(page)).toHaveCount(30);
  await expect(meetingRows(page)).toHaveCount(0);

  const requests = [];
  page.on('request', (request) => {
    if (new URL(request.url()).pathname.startsWith(`/profiles/${research.profileId}/`)) {
      requests.push({ method: request.method(), path: new URL(request.url()).pathname });
    }
  });
  const originalUrl = page.url();

  for (const query of ['SENSORY', 'vestibular', 'WEIGHTED BLANKET', 'hallway', 'OCCUPATIONAL EVALUATION']) {
    await search.fill(query);
    await expect(answerChoices(page).filter({ visible: true })).toHaveCount(1);
    await expect(answerChoice(page, first)).toBeVisible();
  }
  await answerChoice(page, first).check();
  await search.fill('%');
  await expect(answerChoices(page).filter({ visible: true })).toHaveCount(1);
  await search.press('Enter');
  await expect(search).toHaveValue('%');
  await expect(answerChoice(page, first)).toBeChecked();
  await expect(page.getByTestId('meeting-prep-selection-count')).toContainText('1');
  expect(requests).toEqual([]);
  await answerChoice(page, second).check();
  await search.fill('_');
  await expect(answerChoices(page).filter({ visible: true })).toHaveCount(1);
  await answerChoice(page, third).check();
  await search.fill('%');
  await expect(answerChoice(page, second)).toBeChecked();
  await answerChoice(page, second).uncheck();
  await search.fill('nothing-matches-this-research');
  await expect(answerChoices(page).filter({ visible: true })).toHaveCount(0);
  await expect(page.getByTestId('meeting-prep-selection-count')).toContainText('2');
  await expect(submit).toHaveText('Add 2 answers');
  expect(requests).toEqual([]);

  await submitBatch(page);
  await expect(meetingRows(page)).toHaveCount(2);
  await expect(meetingRows(page).filter({ hasText: first.title })).toHaveCount(1);
  await expect(meetingRows(page).filter({ hasText: third.title })).toHaveCount(1);
  await expect(answerChoice(page, first)).toHaveCount(0);
  await expect(answerChoice(page, third)).toHaveCount(0);
  await expect(search).toHaveValue('nothing-matches-this-research');
  await expect(page.getByTestId('meeting-prep-selection-count')).toContainText('0');
  await expect(submit).toHaveAttribute('aria-disabled', 'true');
  await expect(submit).toBeFocused();
  expect(page.url()).toBe(originalUrl);
  expect(requests).toEqual([{ method: 'POST', path: `/profiles/${research.profileId}/meeting-prep/${research.emptyMeetingId}/answers` }]);

  await page.getByTestId('meeting-prep-picker-clear').click();
  await expect(answerChoices(page).filter({ visible: true })).toHaveCount(28);
  await expect(answerChoice(page, second)).not.toBeChecked();
  await page.reload();
  await expect(meetingRows(page)).toHaveCount(2);
  await expect(meetingRows(page).filter({ hasText: first.title })).toHaveCount(1);
  await expect(meetingRows(page).filter({ hasText: third.title })).toHaveCount(1);
  await expectAccessible(page);
});

test('the answer picker shows more choices on desktop and fits smaller screens without hiding its controls', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await openResearch(page, `meeting-prep/${research.emptyMeetingId}`);
  const choices = page.getByRole('group', { name: 'Available saved answers', exact: true });
  const search = page.getByTestId('meeting-prep-picker-search');
  const submit = page.getByTestId('meeting-prep-add-answer');
  const longPreview = answerChoice(page, research.answers[4]).locator('..').getByTestId('meeting-prep-answer-preview');
  await expect(answerChoices(page)).toHaveCount(30);
  let previousHeight = Infinity;

  for (const viewport of [
    { width: 1280, height: 900, name: 'desktop' },
    { width: 390, height: 844, name: 'phone' },
    { width: 390, height: 520, name: 'short-phone' },
  ]) {
    await test.step(viewport.name, async () => {
      await page.setViewportSize({ width: viewport.width, height: viewport.height });
      await choices.evaluate((element) => { element.scrollTop = 0; });
      await choices.scrollIntoViewIfNeeded();
      const layout = await choices.evaluate((element) => {
        const bounds = element.getBoundingClientRect();
        const visibleRows = Array.from(element.querySelectorAll('label')).filter((row) => {
          const rect = row.getBoundingClientRect();
          return rect.top >= bounds.top && rect.bottom <= bounds.bottom;
        }).length;
        return { height: element.clientHeight, scrollHeight: element.scrollHeight, visibleRows };
      });
      expect(layout.scrollHeight).toBeGreaterThan(layout.height);
      expect(layout.height).toBeLessThan(previousHeight);
      expect(layout.height).toBeLessThan(viewport.height * 0.65);
      expect(layout.visibleRows).toBeGreaterThanOrEqual(viewport.name === 'desktop' ? 5 : 2);
      previousHeight = layout.height;
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      expect(await longPreview.evaluate((element) => element.getBoundingClientRect().height
        <= parseFloat(getComputedStyle(element).lineHeight) + 1)).toBe(true);
      if (viewport.name !== 'desktop') {
        expect(await longPreview.evaluate((element) => element.scrollWidth > element.clientWidth)).toBe(true);
      }

      const controlsBefore = await Promise.all([search.boundingBox(), submit.boundingBox()]);
      const reachableChoices = await choices.evaluate((element) => {
        const seen = new Set();
        const inputs = Array.from(element.querySelectorAll('input[type="checkbox"]'));
        const maximum = element.scrollHeight - element.clientHeight;
        for (let offset = 0; offset < maximum + element.clientHeight; offset += element.clientHeight / 2) {
          element.scrollTop = Math.min(offset, maximum);
          const bounds = element.getBoundingClientRect();
          inputs.forEach((input) => {
            const rect = input.getBoundingClientRect();
            if (rect.top >= bounds.top && rect.bottom <= bounds.bottom) seen.add(input.id);
          });
        }
        return seen.size;
      });
      expect(reachableChoices).toBe(30);
      expect(await Promise.all([search.boundingBox(), submit.boundingBox()])).toEqual(controlsBefore);
      await answerChoices(page).last().check();
      await expect(answerChoices(page).last()).toBeChecked();
      await expect(submit).toHaveText('Add 1 answer');
      await answerChoices(page).last().uncheck();
      await choices.evaluate((element) => { element.scrollTop = 0; });
      if (viewport.name !== 'short-phone') {
        await choices.scrollIntoViewIfNeeded();
        await page.screenshot({ path: test.info().outputPath(`answer-picker-${viewport.name}.png`) });
      }
    });
  }
});

test('phone preparation preserves searches, opened answers, sources, selections, scroll, and focus through mutations', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await openResearch(page, `meeting-prep/${research.emptyMeetingId}`);
  const [first, second, third] = research.answers;
  const chosenAnswers = research.answers.slice(0, 10);
  for (const answer of chosenAnswers) await answerChoice(page, answer).check();
  await submitBatch(page);
  await expect(meetingRows(page)).toHaveCount(10);

  const firstRow = meetingRows(page).filter({ hasText: first.title });
  const secondRow = meetingRows(page).filter({ hasText: second.title });
  const thirdRow = meetingRows(page).filter({ hasText: third.title });
  const pickerSearch = page.getByTestId('meeting-prep-picker-search');
  const meetingSearch = page.getByTestId('meeting-prep-filter');
  await pickerSearch.fill('item 11');
  await answerChoice(page, research.answers[10]).check();
  await pickerSearch.fill('item 12');
  await answerChoice(page, research.answers[11]).check();
  await meetingSearch.fill('preparation');
  await expect(meetingRows(page).filter({ visible: true })).toHaveCount(9);
  await meetingSearch.fill('');
  await firstRow.locator('summary').click();
  await firstRow.getByRole('button', { name: 'Show sources' }).click();
  await secondRow.locator('summary').click();
  await meetingSearch.fill('a');
  await expect(meetingRows(page).filter({ visible: true })).toHaveCount(10);

  const originalUrl = page.url();
  const mutations = [];
  const unexpectedRequests = [];
  page.on('request', (request) => {
    const path = new URL(request.url()).pathname;
    if (!path.startsWith(`/profiles/${research.profileId}/`)) return;
    if (request.method() === 'POST' && path.includes(`/meeting-prep/${research.emptyMeetingId}/answers`)) mutations.push(path);
    else unexpectedRequests.push(`${request.method()} ${path}`);
  });
  await page.evaluate(() => {
    document.addEventListener('turbo:submit-start', () => {
      document.body.dataset.meetingSubmitScrollY = String(window.scrollY);
    });
  });
  const orderBefore = await meetingRows(page).evaluateAll((elements) => elements.map((element) => element.getAttribute('data-testid')));
  const firstId = await firstRow.getAttribute('data-testid');
  const firstIndex = orderBefore.indexOf(firstId);
  const moveDirection = firstIndex === orderBefore.length - 1 ? 'up' : 'down';
  const move = firstRow.getByTestId(`meeting-prep-answer-${moveDirection}`);
  await move.click();
  const expectedOrder = [...orderBefore];
  const destination = firstIndex + (moveDirection === 'up' ? -1 : 1);
  [expectedOrder[firstIndex], expectedOrder[destination]] = [expectedOrder[destination], expectedOrder[firstIndex]];
  await expect.poll(() => meetingRows(page).evaluateAll((elements) => elements.map((element) => element.getAttribute('data-testid')))).toEqual(expectedOrder);
  await expect(move).toBeFocused();
  await expectScrollPreserved(page);
  await expect(firstRow.locator('details')).toHaveAttribute('open', '');
  await expect(secondRow.locator('details')).toHaveAttribute('open', '');
  await expect(firstRow.getByRole('button', { name: 'Hide sources' })).toHaveAttribute('aria-expanded', 'true');
  await expect(firstRow.getByText('Try a predictable arrival routine.', { exact: true })).toBeVisible();
  await expect(meetingSearch).toHaveValue('a');
  await expect(pickerSearch).toHaveValue('item 12');
  await expect(answerChoice(page, research.answers[10])).toBeChecked();
  await expect(answerChoice(page, research.answers[11])).toBeChecked();

  await thirdRow.getByTestId('meeting-prep-answer-remove').click();
  await expect(meetingRows(page)).toHaveCount(9);
  await expect(thirdRow).toHaveCount(0);
  await expectScrollPreserved(page);
  await expect.poll(() => page.evaluate(() => document.activeElement?.tagName)).toBe('SUMMARY');
  await expect(firstRow.locator('details')).toHaveAttribute('open', '');
  await expect(secondRow.locator('details')).toHaveAttribute('open', '');
  await expect(firstRow.getByText('Try a predictable arrival routine.', { exact: true })).toBeVisible();
  await expect(meetingSearch).toHaveValue('a');
  await expect(pickerSearch).toHaveValue('item 12');
  await expect(page.getByTestId('meeting-prep-selection-count')).toContainText('2');
  await expect(answerChoice(page, research.answers[10])).toBeChecked();
  await expect(answerChoice(page, research.answers[11])).toBeChecked();

  await meetingSearch.fill('hallway');
  await expect(meetingRows(page).filter({ visible: true })).toHaveCount(1);
  await submitBatch(page);
  await expect(meetingRows(page)).toHaveCount(11);
  await expectScrollPreserved(page);
  await expect(meetingSearch).toHaveValue('hallway');
  await expect(pickerSearch).toHaveValue('item 12');
  await expect(meetingRows(page).filter({ visible: true })).toHaveCount(1);
  await expect(firstRow.locator('details')).toHaveAttribute('open', '');
  await expect(firstRow.getByText('Try a predictable arrival routine.', { exact: true })).toBeVisible();
  await expect(page.getByTestId('meeting-prep-add-answer')).toBeFocused();
  await page.getByTestId('meeting-prep-filter-clear').click();
  await expect(secondRow.locator('details')).toHaveAttribute('open', '');
  await expect(meetingRows(page).filter({ visible: true })).toHaveCount(11);
  expect(mutations).toHaveLength(3);
  expect(unexpectedRequests).toEqual([]);
  expect(page.url()).toBe(originalUrl);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await expectAccessible(page);
  await page.reload();
  await expect(meetingRows(page)).toHaveCount(11);
  await expect(meetingRows(page).filter({ hasText: third.title })).toHaveCount(0);
});

test('removing the last meeting answer keeps an unsubmitted selection and both searches ready for the next add', async ({ page }) => {
  await openResearch(page, `meeting-prep/${research.emptyMeetingId}`);
  const [first, second] = research.answers;
  await answerChoice(page, first).check();
  await submitBatch(page);
  await expect(meetingRows(page)).toHaveCount(1);
  await page.getByTestId('meeting-prep-filter').fill('hallway');
  await page.getByTestId('meeting-prep-picker-search').fill('Literal');
  await answerChoice(page, second).check();
  await meetingRows(page).first().getByTestId('meeting-prep-answer-remove').click();
  await expect(meetingRows(page)).toHaveCount(0);
  await expect(page.getByRole('heading', { name: 'No answers in this meeting yet', exact: true })).toBeVisible();
  await expect(page.getByTestId('meeting-prep-filter')).toHaveValue('hallway');
  await expect(page.getByTestId('meeting-prep-filter')).toBeFocused();
  await expect(page.getByTestId('meeting-prep-picker-search')).toHaveValue('Literal');
  await expect(answerChoice(page, second)).toBeChecked();
  await expect(page.getByTestId('meeting-prep-add-answer')).toHaveText('Add 1 answer');

  await submitBatch(page);
  await expect(meetingRows(page)).toHaveCount(1);
  await expect(meetingRows(page).filter({ visible: true })).toHaveCount(0);
  await expect(page.getByTestId('meeting-prep-filter-empty')).toBeVisible();
  await page.getByTestId('meeting-prep-filter-clear').click();
  await expect(meetingRows(page).first()).toContainText(second.title);
  await page.getByTestId('meeting-prep-picker-clear').click();
  await expect(answerChoice(page, first)).toBeVisible();
  await expect(answerChoice(page, first)).not.toBeChecked();
  await page.reload();
  await expect(meetingRows(page)).toHaveCount(1);
  await expect(meetingRows(page).first()).toContainText(second.title);
});

test('a rejected batch keeps selected answers and searches so the user can retry', async ({ page }) => {
  await openResearch(page, `meeting-prep/${research.emptyMeetingId}`);
  const [first, second] = research.answers;
  const search = page.getByTestId('meeting-prep-picker-search');
  await search.fill('sensory');
  await answerChoice(page, first).check();
  await search.fill('Literal');
  await answerChoice(page, second).check();
  await page.getByTestId('meeting-prep-filter').fill('hallway');

  const path = `/profiles/${research.profileId}/meeting-prep/${research.emptyMeetingId}/answers`;
  // Remove the submitted ids once to exercise the server's real validation response.
  await page.route(`**${path}`, async (route) => {
    const form = new URLSearchParams(route.request().postData() || '');
    form.delete('saved_answer_ids[]');
    const response = await route.fetch({ postData: form.toString() });
    await route.fulfill({ response });
  }, { times: 1 });
  const [response] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === 'POST'
      && new URL(response.url()).pathname === path),
    page.getByTestId('meeting-prep-add-answer').click(),
  ]);
  expect(response.status()).toBe(422);
  await expect(page.getByTestId('meeting-prep-status')).toContainText('Choose at least one saved answer');
  await expect(meetingRows(page)).toHaveCount(0);
  await expect(search).toHaveValue('Literal');
  await expect(page.getByTestId('meeting-prep-filter')).toHaveValue('hallway');
  await expect(answerChoice(page, first)).toBeChecked();
  await expect(answerChoice(page, second)).toBeChecked();
  await expect(page.getByTestId('meeting-prep-add-answer')).toHaveText('Add 2 answers');
  await expect(page.getByTestId('meeting-prep-add-answer')).toHaveAttribute('aria-disabled', 'false');
  await expect(page.getByTestId('meeting-prep-add-answer')).toBeFocused();

  await submitBatch(page);
  await expect(meetingRows(page)).toHaveCount(2);
  await expect(page.getByTestId('meeting-prep-status')).toContainText('2 answers added to meeting');
  await expect(meetingRows(page).filter({ visible: true })).toHaveCount(1);
  await expect(meetingRows(page).filter({ visible: true }).first()).toContainText(first.title);
  await page.reload();
  await expect(meetingRows(page)).toHaveCount(2);
});

test('a thirty-answer meeting filters instantly on a phone and Clear restores its order without requests', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await openResearch(page, `meeting-prep/${research.meetingId}`);
  await expect(meetingRows(page)).toHaveCount(30);
  const originalOrder = await meetingRows(page).evaluateAll((elements) => elements.map((element) => element.getAttribute('data-testid')));
  const originalUrl = page.url();
  const filteringRequests = [];
  page.on('request', (request) => {
    if (['document', 'xhr', 'fetch'].includes(request.resourceType())) filteringRequests.push(request.url());
  });

  for (const query of ['SENSORY', 'vestibular', 'WEIGHTED BLANKET', 'hallway', 'OCCUPATIONAL EVALUATION', '%', '_']) {
    await page.getByTestId('meeting-prep-filter').fill(query);
    await expect(meetingRows(page).filter({ visible: true })).toHaveCount(1);
    await expect(page.getByTestId('meeting-prep-filter-count')).toContainText('1');
  }
  await page.getByTestId('meeting-prep-filter').fill('nothing-matches-this-research');
  await expect(meetingRows(page).filter({ visible: true })).toHaveCount(0);
  await expect(page.getByTestId('meeting-prep-filter-empty')).toBeVisible();
  await page.getByTestId('meeting-prep-filter-clear').click();
  await expect(meetingRows(page).filter({ visible: true })).toHaveCount(30);
  expect(await meetingRows(page).evaluateAll((elements) => elements.map((element) => element.getAttribute('data-testid')))).toEqual(originalOrder);
  const firstAnswer = meetingRows(page).first();
  await firstAnswer.locator('summary').click();
  await expect(firstAnswer.getByText('Bring the weighted blanket plan')).toBeVisible();
  await expect(firstAnswer.getByText('Discuss hallway transitions.', { exact: true })).toBeVisible();
  await firstAnswer.getByRole('button', { name: 'Show sources' }).click();
  await expect(firstAnswer.getByText('Try a predictable arrival routine.', { exact: true })).toBeVisible();
  expect(page.url()).toBe(originalUrl);
  expect(filteringRequests).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await expectAccessible(page);
});

test('removing an original source keeps its saved answer and source label readable', async ({ page }) => {
  await openResearch(page, `saved-answers/${research.answers[0].id}`);
  await expect(page.getByRole('link', { name: /Open source 1: Occupational evaluation/ }).first()).toBeVisible();
  removeSavedResearchSource(research.profileId, research.sourceId);
  await page.reload();
  await page.getByRole('button', { name: 'Show sources' }).click();
  await expect(page.getByText('Bring the weighted blanket plan')).toBeVisible();
  await expect(page.getByText('Occupational evaluation, page 2', { exact: true })).toBeVisible();
  await expect(page.getByText('Original document is no longer available.')).toBeVisible();
  await expect(page.getByText('Try a predictable arrival routine.', { exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: /Open source 1:/ })).toHaveCount(0);
});
