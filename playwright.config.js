// @ts-check
import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.QA_BASE_URL || 'http://127.0.0.1:3100';
const alwaysRecordArtifacts = process.env.QA_ARTIFACT_MODE === 'always';

export default defineConfig({
  testDir: './tests/e2e',
  outputDir: 'tmp/qa-artifacts/test-results',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['list'],
    ['html', { outputFolder: 'tmp/qa-artifacts/playwright-report', open: 'never' }],
  ],
  use: {
    baseURL,
    screenshot: alwaysRecordArtifacts ? 'on' : 'only-on-failure',
    trace: alwaysRecordArtifacts ? 'on' : 'retain-on-failure',
    video: alwaysRecordArtifacts ? 'on' : 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
  ],
});
