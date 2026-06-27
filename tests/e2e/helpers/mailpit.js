// @ts-check
import { expect } from '@playwright/test';

const MAILPIT_API_URL = process.env.QA_MAILPIT_API_URL;

export async function clearMailpit(request) {
  const response = await request.delete(`${MAILPIT_API_URL}/api/v1/messages`, { data: {} });
  expect(response.ok(), `Mailpit inbox cleanup failed with ${response.status()}`).toBeTruthy();
}

export async function waitForMailpitMessage(request, predicate, options = {}) {
  const timeoutMs = options.timeoutMs || 5000;
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    const messages = await listMailpitMessages(request);
    const message = messages.find(predicate);
    if (message) return message;

    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  const messages = await listMailpitMessages(request);
  throw new Error(`No matching Mailpit message found. Messages: ${JSON.stringify(messages)}`);
}

export async function expectNoMailpitMessages(request) {
  const messages = await listMailpitMessages(request);
  expect(messages).toEqual([]);
}

export async function getMailpitMessageText(request, messageId) {
  const response = await request.get(`${MAILPIT_API_URL}/view/${messageId}.txt`);
  expect(response.ok(), `Mailpit text view failed with ${response.status()}`).toBeTruthy();
  return response.text();
}

async function listMailpitMessages(request) {
  if (!MAILPIT_API_URL) {
    throw new Error('QA_MAILPIT_API_URL is required for Mailpit QA checks.');
  }

  const response = await request.get(`${MAILPIT_API_URL}/api/v1/messages`);
  expect(response.ok(), `Mailpit message list failed with ${response.status()}`).toBeTruthy();
  const body = await response.json();
  return body.messages || [];
}
