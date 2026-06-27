// @ts-check
import { test as base } from '@playwright/test';
import { installDiagnostics } from './helpers/diagnostics';

export const test = base.extend({
  page: async ({ page }, use) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    const expectNoDiagnostics = installDiagnostics(page);
    await use(page);
    await expectNoDiagnostics();
  },
});

export { expect } from '@playwright/test';
