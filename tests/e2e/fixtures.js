// @ts-check
import { test as base } from '@playwright/test';
import { installDiagnostics } from './helpers/diagnostics';
import { createBrowserFamily, deleteBrowserFamily, rememberBrowserFamilyBlobs } from './helpers/family';
import { signIn, openDependentWorkspace } from './helpers/auth';

export const test = base.extend({
  family: async ({}, use) => {
    const family = createBrowserFamily();
    try {
      await use({
        ...family,
        signIn: (page) => signIn(page, { user: family.user }),
        openDependentWorkspace: (page) => openDependentWorkspace(page, { user: family.user }),
        rememberBlobs: () => rememberBrowserFamilyBlobs(family),
      });
    } finally {
      deleteBrowserFamily(family);
    }
  },
  page: async ({ page }, use) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    const expectNoDiagnostics = installDiagnostics(page);
    await use(page);
    await expectNoDiagnostics();
  },
});

export { expect } from '@playwright/test';
