// @ts-check
import { execFileSync } from 'node:child_process';

export function setAccountSubscription(accountName, attributes) {
  runRailsRunner(
    `
      account = Account.find_by!(name: ENV.fetch("QA_ACCOUNT_NAME"))
      subscription = account.billing_subscription || account.build_billing_subscription
      attributes = JSON.parse(ENV.fetch("QA_SUBSCRIPTION_ATTRIBUTES"))
      subscription.assign_attributes(attributes)
      subscription.save!
    `,
    {
      QA_ACCOUNT_NAME: accountName,
      QA_SUBSCRIPTION_ATTRIBUTES: JSON.stringify(attributes),
    },
  );
}

function runRailsRunner(code, env = {}) {
  execFileSync('bin/rails', ['runner', code], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      ...env,
      RAILS_ENV: 'test',
    },
    stdio: 'pipe',
  });
}
