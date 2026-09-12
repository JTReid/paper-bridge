// @ts-check
import { execFileSync } from 'node:child_process';

// Mutable workflows get the familiar fixture family in their own account.
// Originals are copied into new blobs so teardown cannot purge shared files.
export function createBrowserFamily() {
  return run(`
    ${familyBlobIds}
    family = ActiveRecord::Base.transaction do
      template = User.find_by!(email: "admin@example.test").account
      token = SecureRandom.hex(8)
      user = User.create!(name: "Browser QA Admin", email: "browser-family-#{token}@example.test", password: "password")
      account = Account.create!(name: "Browser QA Family #{token}")
      user.account_memberships.create!(account: account, role: :admin)
      account.create_billing_subscription!(status: :active, stripe_price_id: "price_fixture_standard")

      %w[Emma Noah].each do |first_name|
        source = template.dependents.find_by!(first_name: first_name, last_name: "Greenfield")
        profile = source.dup
        profile.account = account
        profile.save!
        source.appointments.each { |appointment| appointment.dup.update!(dependent: profile) }
        source.care_team_memberships.each do |contact|
          contact.dup.update!(account: account, dependent: profile, invited_by: user)
        end
        source.documents.each do |original|
          document = original.dup
          document.assign_attributes(account: account, dependent: profile, user: user)
          document.file.attach(io: StringIO.new(original.file.download), filename: original.file.filename.to_s, content_type: original.file.content_type)
          document.save!
          original.document_pages.each do |original_page|
            page = original_page.dup
            page.update!(account: account, document: document)
            original_page.document_chunks.each do |chunk|
              chunk.dup.update!(account: account, document: document, document_page: page)
            end
          end
        end
      end

      { accountId: account.id, accountName: account.name, userId: user.id, user: { email: user.email, password: "password" }, blobIds: browser_family_blob_ids(account) }
    end
    puts JSON.generate(family)
  `);
}

// Remember uploads before a browser deletion removes their attachment links.
export function rememberBrowserFamilyBlobs(family) {
  const ids = run(`
    ${familyBlobIds}
    account = Account.find(ENV.fetch("QA_FAMILY_ACCOUNT_ID"))
    raise "Not a browser QA family" unless account.name.start_with?("Browser QA Family ")
    puts JSON.generate(browser_family_blob_ids(account))
  `, { QA_FAMILY_ACCOUNT_ID: String(family.accountId) });
  family.blobIds = [...new Set([...family.blobIds, ...ids])];
}

export function deleteBrowserFamily(family) {
  run(`
    ${familyBlobIds}
    account = Account.find_by(id: ENV.fetch("QA_FAMILY_ACCOUNT_ID"))
    user = User.find_by(id: ENV.fetch("QA_FAMILY_USER_ID"))
    raise "Not a browser QA family" if account && !account.name.start_with?("Browser QA Family ")
    raise "Not a browser QA user" if user && !user.email.match?(/\\Abrowser-family-[a-f0-9]+@example\\.test\\z/)
    blob_ids = JSON.parse(ENV.fetch("QA_FAMILY_BLOB_IDS"))
    blob_ids.concat(browser_family_blob_ids(account)) if account
    ActiveRecord::Base.transaction do
      account&.destroy!
      user&.destroy!
    end
    # TestAdapter does not execute the PurgeJobs scheduled by attachment teardown.
    # Purge only this test's now-unattached files, after deletion has committed.
    ActiveStorage::Blob.where(id: blob_ids).find_each do |blob|
      blob.purge unless blob.attachments.exists?
    end
    puts "null"
  `, {
    QA_FAMILY_ACCOUNT_ID: String(family.accountId), QA_FAMILY_USER_ID: String(family.userId),
    QA_FAMILY_BLOB_IDS: JSON.stringify(family.blobIds),
  });
}

const familyBlobIds = `
  def browser_family_blob_ids(account)
    ActiveStorage::Attachment.where(record_type: "Document", record_id: account.documents.select(:id), name: "file")
      .or(ActiveStorage::Attachment.where(record_type: "DocumentPage", record_id: account.document_pages.select(:id), name: "image"))
      .or(ActiveStorage::Attachment.where(record_type: "Dependent", record_id: account.dependents.select(:id), name: "avatar"))
      .distinct.pluck(:blob_id)
  end
`;

function run(code, env = {}) {
  const output = execFileSync('bin/rails', ['runner', `raise "Browser family fixtures require test" unless Rails.env.test?\n${code}`], {
    cwd: process.cwd(), env: { ...process.env, ...env, RAILS_ENV: 'test' }, stdio: 'pipe', encoding: 'utf8',
  });
  return JSON.parse(output.trim().split('\n').at(-1));
}
