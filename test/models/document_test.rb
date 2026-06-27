require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  test "belongs to an account and has one attached file" do
    document = build_document

    assert document.valid?
    assert document.file.attached?
  end

  test "requires an attached file" do
    document = Document.new(
      account: accounts(:greenfield),
      dependent: dependents(:emma),
      user: users(:family_admin),
      title: "Trust"
    )

    assert_not document.valid?
    assert_includes document.errors[:file], "must be attached"
  end

  test "caches file metadata" do
    document = build_document(title: nil)
    document.validate

    assert_equal "sample", document.title
    assert_equal "sample.txt", document.original_filename
    assert_equal "text/plain", document.content_type
    assert_equal file_fixture("sample.txt").size, document.byte_size
  end

  test "does not default blank title on persisted documents" do
    document = documents(:advance_directive)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: "sample.txt",
      content_type: "text/plain"
    )

    document.title = ""

    assert_not document.valid?
    assert_includes document.errors[:title], "can't be blank"
  end

  test "requires document account to match uploading user account" do
    document = build_document(account: accounts(:other))

    assert_not document.valid?
    assert_includes document.errors[:account], "must be manageable by the uploading user"
  end

  test "requires document account to match dependent account" do
    document = build_document(dependent: dependents(:other_dependent))

    assert_not document.valid?
    assert_includes document.errors[:account], "must match the dependent"
  end

  test "queues processing after create commit" do
    document = build_document

    assert_enqueued_with(job: ProcessDocumentJob) do
      document.save!
    end

    assert_equal "queued", document.reload.status
  end

  private

    def build_document(account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin), title: "Trust")
      Document.new(
        account: account,
        dependent: dependent,
        user: user,
        title: title,
        category: :general,
        file: {
          io: file_fixture("sample.txt").open,
          filename: "sample.txt",
          content_type: "text/plain"
        }
      )
    end
end
