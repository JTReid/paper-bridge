// @ts-check
import { execFileSync } from 'node:child_process';

export function createDocumentListScenario() {
  return run(`
    user = User.find_by!(email: "admin@example.test")
    profile = user.account.dependents.create!(first_name: "DocumentList", last_name: "QA-#{SecureRandom.hex(6)}")
    documents = %w[alpha beta gamma].map do |name|
      document = profile.documents.new(account: user.account, user: user, initial_metadata_pending: true)
      document.file.attach(io: StringIO.new("Synthetic #{name} source for document list browser QA."), filename: "#{name}-record.txt", content_type: "text/plain")
      document.save!
      { id: document.id, title: document.title }
    end
    puts JSON.generate(profileId: profile.id, documents: documents)
  `);
}

export function updateListDocument(profileId, documentId, attributes) {
  return run(`
    ${profileLookup}
    document = profile.documents.find(ENV.fetch("QA_DOCUMENT_ID"))
    attributes = JSON.parse(ENV.fetch("QA_DOCUMENT_ATTRIBUTES"))
    document.update!(attributes.merge("initial_metadata_pending" => false))
    stream = "#{profile.account.to_gid_param}:#{profile.to_gid_param}:documents"
    puts JSON.generate(ActionCable.server.pubsub.broadcasts(stream).map { |message| JSON.parse(message) })
  `, {
    QA_PROFILE_ID: String(profileId),
    QA_DOCUMENT_ID: String(documentId),
    QA_DOCUMENT_ATTRIBUTES: JSON.stringify(attributes),
  });
}

export function deleteDocumentListScenario(profileId) {
  run(`
    ${profileLookup}
    profile.documents.find_each(&:destroy!)
    profile.destroy!
    puts "null"
  `, { QA_PROFILE_ID: String(profileId) });
}

const profileLookup = `
  profile = User.find_by!(email: "admin@example.test").account.dependents.find(ENV.fetch("QA_PROFILE_ID"))
  raise "Not a document list QA profile" unless profile.first_name == "DocumentList" && profile.last_name.start_with?("QA-")
`;

function run(code, env = {}) {
  const output = execFileSync('bin/rails', ['runner', code], {
    cwd: process.cwd(),
    env: { ...process.env, ...env, RAILS_ENV: 'test' },
    stdio: 'pipe',
    encoding: 'utf8',
  });
  return JSON.parse(output.trim().split('\n').at(-1));
}
