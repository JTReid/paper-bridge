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

export function createAccountProfiles(accountName, profiles) {
  runRailsRunner(
    `
      account = Account.find_by!(name: ENV.fetch("QA_ACCOUNT_NAME"))
      JSON.parse(ENV.fetch("QA_PROFILES")).each do |attributes|
        account.dependents.create!(attributes.slice("first_name", "last_name"))
      end
    `,
    {
      QA_ACCOUNT_NAME: accountName,
      QA_PROFILES: JSON.stringify(profiles),
    },
  );
}

export function deleteAccountProfilesByLastName(accountName, lastName) {
  runRailsRunner(
    `
      account = Account.find_by!(name: ENV.fetch("QA_ACCOUNT_NAME"))
      account.dependents.where(last_name: ENV.fetch("QA_PROFILE_LAST_NAME")).find_each(&:destroy!)
    `,
    {
      QA_ACCOUNT_NAME: accountName,
      QA_PROFILE_LAST_NAME: lastName,
    },
  );
}

export function clearAiAssistantQueries(accountName) {
  runRailsRunner(
    `
      account = Account.find_by!(name: ENV.fetch("QA_ACCOUNT_NAME"))
      AiAssistantQuery.where(account: account).find_each(&:destroy!)
    `,
    { QA_ACCOUNT_NAME: accountName },
  );
}

export function resetLatestAiAssistantQueryStart(accountName) {
  runRailsRunner(
    `
      account = Account.find_by!(name: ENV.fetch("QA_ACCOUNT_NAME"))
      account.ai_assistant_queries.order(created_at: :desc).first!.update!(enqueued_at: nil)
    `,
    { QA_ACCOUNT_NAME: accountName },
  );
}

export function completeLatestAiAssistantQueryWithoutBroadcast(accountName, answer) {
  runRailsRunner(
    `
      account = Account.find_by!(name: ENV.fetch("QA_ACCOUNT_NAME"))
      query = account.ai_assistant_queries.order(created_at: :desc).first!
      query.update_columns(
        state: "completed",
        answer: { answer: ENV.fetch("QA_ANSWER"), citations: [], limitations: [] },
        result_count: 1,
        completed_at: Time.current,
        updated_at: Time.current
      )
    `,
    {
      QA_ACCOUNT_NAME: accountName,
      QA_ANSWER: answer,
    },
  );
}

export function completeDocumentInitialMetadata(documentId, metadata) {
  const output = runRailsRunner(
    `
      document = Document.find(ENV.fetch("QA_DOCUMENT_ID"))
      metadata = JSON.parse(ENV.fetch("QA_DOCUMENT_METADATA"))
      document.complete_initial_metadata!(
        category: metadata.fetch("category"),
        description: metadata.fetch("description")
      )
      broadcasts = ActionCable.server.pubsub.broadcasts(document.to_gid_param)
      puts JSON.generate(broadcasts.map { |message| JSON.parse(message) })
    `,
    {
      QA_DOCUMENT_ID: String(documentId),
      QA_DOCUMENT_METADATA: JSON.stringify(metadata),
    },
  );

  return JSON.parse(output);
}

export function deleteAccountsAndUsers(accounts) {
  runRailsRunner(
    `
      accounts = JSON.parse(ENV.fetch("QA_ACCOUNTS"))
      Account.where(name: accounts.pluck("accountName")).find_each(&:destroy!)
      User.where(email: accounts.pluck("email")).find_each(&:destroy!)
    `,
    {
      QA_ACCOUNTS: JSON.stringify(accounts),
    },
  );
}

function runRailsRunner(code, env = {}) {
  return execFileSync('bin/rails', ['runner', code], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      ...env,
      RAILS_ENV: 'test',
    },
    stdio: 'pipe',
    encoding: 'utf8',
  });
}
