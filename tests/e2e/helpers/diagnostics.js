// @ts-check
import { expect } from '@playwright/test';

const IGNORED_CONSOLE_ERROR_PATTERNS = [
  /favicon/i,
  /server responded with a status of 422/i,
];

const IGNORED_PAGE_ERROR_PATTERNS = [
  /AbortError: The user aborted a request/i,
];

export function installDiagnostics(page) {
  const consoleErrors = [];
  const pageErrors = [];
  const failedResponses = [];
  const failedRequests = [];

  page.on('console', (message) => {
    if (message.type() !== 'error') return;

    const text = message.text();
    if (IGNORED_CONSOLE_ERROR_PATTERNS.some((pattern) => pattern.test(text))) return;

    consoleErrors.push(text);
  });

  page.on('pageerror', (error) => {
    const text = `${error.name}: ${error.message}`;
    if (IGNORED_PAGE_ERROR_PATTERNS.some((pattern) => pattern.test(text))) return;

    pageErrors.push(text);
  });

  page.on('response', (response) => {
    if (response.status() >= 500) {
      failedResponses.push(`${response.status()} ${response.url()}`);
    }
  });

  page.on('requestfailed', (request) => {
    failedRequests.push(`${request.failure()?.errorText || 'failed'} ${request.url()}`);
  });

  return async function expectNoDiagnostics() {
    expect.soft(pageErrors, 'Uncaught browser page errors').toEqual([]);
    expect.soft(consoleErrors, 'Browser console errors').toEqual([]);
    expect.soft(failedResponses, 'HTTP responses with status >= 500').toEqual([]);
    expect.soft(failedRequests, 'Failed browser requests').toEqual([]);
  };
}
