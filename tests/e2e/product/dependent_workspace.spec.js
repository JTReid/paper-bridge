// @ts-check
import { test, expect } from '@playwright/test';
import { openDependentWorkspace } from '../helpers/auth';

test('dependent workspace exposes current product navigation', async ({ page }) => {
  await openDependentWorkspace(page);

  await expect(page.getByText('Recent Documents')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Open Assistant' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Care Team' }).last()).toBeVisible();
  await expect(page.getByText('Advance Directive')).toBeVisible();
});
