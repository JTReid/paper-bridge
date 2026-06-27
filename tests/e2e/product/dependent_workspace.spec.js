// @ts-check
import { test, expect } from '../fixtures';
import { openDependentWorkspace } from '../helpers/auth';
import { expectAccessible } from '../helpers/accessibility';

test('dependent workspace exposes current product navigation', async ({ page }) => {
  await openDependentWorkspace(page);

  await expect(page.getByText('Recent Documents')).toBeVisible();
  await expect(page.getByTestId('dependent-ai-assistant-link')).toBeVisible();
  await expect(page.getByTestId('dependent-care-team-link')).toBeVisible();
  await expect(page.getByTestId('dependent-documents-link')).toBeVisible();
  await expect(page.getByText('Advance Directive')).toBeVisible();
  await expectAccessible(page);
});
