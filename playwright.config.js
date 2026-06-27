// @ts-check
import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.QA_BASE_URL || 'http://127.0.0.1:3100';
const alwaysRecordArtifacts = process.env.QA_ARTIFACT_MODE === 'always';
const artifactRoot = process.env.QA_ARTIFACT_DIR || 'tmp/qa-artifacts';

export default defineConfig({
  testDir: './tests/e2e',
  outputDir: `${artifactRoot}/test-results`,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: Number(process.env.QA_WORKERS || 1),
  reporter: [
    ['list'],
    ['html', { outputFolder: `${artifactRoot}/playwright-report`, open: 'never' }],
  ],
  use: {
    baseURL,
    reducedMotion: 'reduce',
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
