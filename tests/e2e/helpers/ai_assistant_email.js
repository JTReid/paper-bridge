// @ts-check
import { execFileSync } from 'node:child_process';

function runScenario(code, profileId) {
  const output = execFileSync('bin/rails', ['runner', code], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      RAILS_ENV: 'test',
      QA_ANSWER_EMAIL_PROFILE_ID: profileId ? String(profileId) : '',
    },
    stdio: 'pipe',
    encoding: 'utf8',
  });
  return JSON.parse(output.trim().split('\n').at(-1));
}

const findScenario = `
  user = User.find_by!(email: "admin@example.test")
  profile = user.account.dependents.find(ENV.fetch("QA_ANSWER_EMAIL_PROFILE_ID"))
  raise "Not an answer email QA profile" unless profile.first_name == "AnswerEmail" && profile.last_name.start_with?("QA-")
`;

export function createAnswerEmailScenario() {
  return runScenario(`
    raise "Answer email QA requires the test environment" unless Rails.env.test?
    scenario = ActiveRecord::Base.transaction do
      user = User.find_by!(email: "admin@example.test")
      account = user.account
      profile = account.dependents.create!(first_name: "AnswerEmail", last_name: "QA-#{SecureRandom.hex(6)}")
      source = profile.documents.new(account: account, user: user, title: "Classroom support evaluation", category: :educational)
      source.file.attach(io: StringIO.new("Original source file must never be emailed with an answer."), filename: "answer-email-source.zip", content_type: "application/zip")
      source.save!
      contact = profile.care_team_memberships.create!(account: account, invited_by: user, name: "Alex Teacher", email: "answer-email-teacher@example.test", role: :teacher)
      question = "Which classroom supports should we discuss?"
      answer_text = "Use a visual schedule [1].\\n\\nOffer a quiet arrival."
      limitation = "The evaluation does not specify how often to use each support."
      quote = "Private source excerpt excluded from answer email."
      query = profile.ai_assistant_queries.create!(
        account: account, user: user, question: question, state: :completed,
        answer: {
          answer: answer_text,
          citations: [{ source_number: 1, document_id: source.id, document_title: source.title, page_number: 2, quote: quote }],
          limitations: [limitation]
        },
        result_count: 1, completed_at: Time.utc(2026, 9, 2, 10, 0)
      )
      { profileId: profile.id, queryId: query.id, question: question, answer: answer_text,
        limitation: limitation, sourceTitle: source.title, sourceQuote: quote, contactEmail: contact.email,
        senderEmail: user.email, originalAnswer: query.answer }
    end
    puts JSON.generate(scenario)
  `);
}

export function answerEmailScenarioState(profileId) {
  return runScenario(`
    ${findScenario}
    puts JSON.generate(queryCount: profile.ai_assistant_queries.count, savedAnswerCount: profile.saved_answers.count, answer: profile.ai_assistant_queries.sole.answer)
  `, profileId);
}

export function deleteAnswerEmailScenario(profileId) {
  return runScenario(`
    ${findScenario}
    ActiveRecord::Base.transaction do
      profile.documents.find_each(&:destroy!)
      profile.destroy!
    end
    puts JSON.generate(deleted: true)
  `, profileId);
}
