// @ts-check
import AxeBuilder from '@axe-core/playwright';
import { expect } from '@playwright/test';

export async function expectAccessible(page, options = {}) {
  const builder = new AxeBuilder({ page });

  if (options.include) {
    for (const selector of options.include) {
      builder.include(selector);
    }
  }

  const results = await builder.analyze();

  expect(results.violations, accessibilityReport(results.violations)).toEqual([]);
}

function accessibilityReport(violations) {
  if (violations.length === 0) return 'No accessibility violations';

  return violations.map((violation) => {
    const nodes = violation.nodes.map((node) => `    - ${node.target.join(', ')}: ${node.failureSummary}`).join('\n');
    return `${violation.id} (${violation.impact}): ${violation.help}\n  ${violation.helpUrl}\n${nodes}`;
  }).join('\n\n');
}
