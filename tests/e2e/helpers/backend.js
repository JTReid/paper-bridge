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

export function createSavedResearchScenario() {
  const output = runRailsRunner(`
    scenario = ActiveRecord::Base.transaction do
      user = User.find_by!(email: "admin@example.test")
      account = user.account
      profile = account.dependents.create!(first_name: "Research", last_name: "QA-#{SecureRandom.hex(6)}")
      source = profile.documents.new(account: account, user: user, title: "Occupational evaluation", category: :therapy)
      source.file.attach(io: StringIO.new("Synthetic source for saved research browser QA."), filename: "research-source.zip", content_type: "application/zip")
      source.save!
      citation = { source_number: 1, document_id: source.id, document_title: source.title, page_number: 2, quote: "Try a predictable arrival routine." }
      meeting = profile.meeting_preps.create!(account: account, user: user, name: "School support meeting")
      empty_meeting = profile.meeting_preps.create!(account: account, user: user, name: "Upcoming planning meeting")
      answers = 30.times.map do |index|
        number = index + 1
        question = index.zero? ? "Which vestibular supports help?" : "Research question #{number}"
        body = if index.zero?
          "Bring the weighted blanket plan [1]."
        elsif index == 4
          "Review the classroom arrival routine with the teacher, including the first activity, a quiet place to settle, and how the family will hear about progress. Keep the full response available when preparing for the meeting."
        else
          "Saved response for research item #{number}."
        end
        query = profile.ai_assistant_queries.create!(
          account: account, user: user, question: question, state: :completed,
          answer: { answer: body, citations: index.zero? ? [citation] : [], limitations: ["Synthetic QA evidence only."] },
          result_count: 1, completed_at: Time.utc(2026, 9, 1, 10, 0)
        )
        saved = SavedAnswer.save_from_query!(query)
        title = case index
        when 0 then "Sensory checklist"
        when 1 then "Literal 100% progress"
        when 2 then "School_ready packet"
        when 3 then "SchoolXready packet"
        when 4 then "Research item 05: Planning the classroom arrival routine and the first activity of the day"
        else "Research item #{number.to_s.rjust(2, '0')}"
        end
        saved.update!(title: title, notes: index.zero? ? "Discuss hallway transitions." : "Preparation note #{number}.")
        entry = meeting.add_answer!(saved)
        { id: saved.id, entryId: entry.id, title: title }
      end
      query = profile.ai_assistant_queries.create!(
        account: account, user: user, question: "Which support should we discuss next?", state: :completed,
        answer: { answer: "Start with visual supports and a calm arrival routine. [1]", citations: [citation], limitations: ["Discuss these suggestions with the care team."] },
        result_count: 1, completed_at: Time.utc(2026, 9, 2, 10, 0)
      )
      { profileId: profile.id, profileName: profile.name, sourceId: source.id, queryId: query.id, meetingId: meeting.id, emptyMeetingId: empty_meeting.id, answers: answers }
    end
    puts JSON.generate(scenario)
  `);
  return JSON.parse(output.trim().split('\n').at(-1));
}

export function deleteSavedResearchScenario(profileId) {
  runRailsRunner(
    `
      profile = User.find_by!(email: "admin@example.test").account.dependents.find_by(id: ENV.fetch("QA_RESEARCH_PROFILE_ID"))
      if profile
        raise "Not a saved research QA profile" unless profile.first_name == "Research" && profile.last_name.start_with?("QA-")
        ActiveRecord::Base.transaction do
          profile.documents.find_each(&:destroy!)
          profile.destroy!
        end
      end
    `,
    { QA_RESEARCH_PROFILE_ID: String(profileId) },
  );
}

export function removeSavedResearchSource(profileId, sourceId) {
  runRailsRunner(
    `
      profile = User.find_by!(email: "admin@example.test").account.dependents.find(ENV.fetch("QA_RESEARCH_PROFILE_ID"))
      raise "Not a saved research QA profile" unless profile.first_name == "Research" && profile.last_name.start_with?("QA-")
      profile.documents.find(ENV.fetch("QA_RESEARCH_SOURCE_ID")).destroy!
    `,
    { QA_RESEARCH_PROFILE_ID: String(profileId), QA_RESEARCH_SOURCE_ID: String(sourceId) },
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
