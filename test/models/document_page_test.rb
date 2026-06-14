require "test_helper"

class DocumentPageTest < ActiveSupport::TestCase
  test "requires page number" do
    page = DocumentPage.new(account: accounts(:greenfield), document: documents(:advance_directive))

    assert_not page.valid?
    assert_includes page.errors[:page_number], "can't be blank"
  end

  test "requires account to match document" do
    page = DocumentPage.new(
      account: accounts(:other),
      document: documents(:advance_directive),
      page_number: 10
    )

    assert_not page.valid?
    assert_includes page.errors[:account], "must match the document"
  end
end
