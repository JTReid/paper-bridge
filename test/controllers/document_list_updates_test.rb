require "test_helper"

class DocumentListUpdatesTest < ActionDispatch::IntegrationTest
  setup do
    @dependent = dependents(:emma)
    sign_in users(:family_admin)
  end

  test "list subscribes to the selected account and profile and retains committed filters" do
    get dependent_documents_path(@dependent, category: "medical", q: " annual ")

    assert_response :success
    source = css_select("turbo-cable-stream-source").sole
    assert_equal "#{accounts(:greenfield).to_gid_param}:#{@dependent.to_gid_param}:documents",
      Turbo::StreamsChannel.verified_stream_name(source["signed-stream-name"])
    assert_select "[data-controller='document-list'][data-document-list-url-value='#{dependent_documents_path(@dependent, q: "annual", category: "medical")}']"
    assert_select "input[data-testid='documents-search-field'][value='annual']"
  end

  test "stream response replaces only filtered rows and counts" do
    matching = create_document(@dependent, "annual-medical.txt", :medical)
    matching.processed!
    excluded = create_document(@dependent, "annual-school.txt", :educational)
    other_profile = create_document(dependents(:noah), "annual-medical.txt", :medical)

    get dependent_documents_path(@dependent, category: "medical", q: "annual"), headers: refresh_headers

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='replace']", count: 2
    assert_select "turbo-stream[target='#{dom_id(@dependent, :documents_counts)}']"
    assert_select "turbo-stream[target='#{dom_id(@dependent, :documents_rows)}']"
    assert_select "[data-testid='document-row-#{matching.id}']", text: /Ready/
    assert_select "[data-testid='document-row-#{excluded.id}']", count: 0
    assert_select "[data-testid='document-row-#{other_profile.id}']", count: 0
    assert_select "[data-testid='documents-total-count']", text: "1"
    assert_select "[data-testid='documents-ready-count']", text: "1"
    assert_select "[data-testid='documents-processing-count']", text: "0"
    assert_select "form, dialog, turbo-cable-stream-source", count: 0
  end

  test "stream response cannot read another account profile" do
    get dependent_documents_path(dependents(:other_dependent)), headers: refresh_headers

    assert_response :not_found
    assert_select "turbo-stream", count: 0
  end

  test "Turbo upload redirect renders the full list and its success message" do
    upload = fixture_file_upload("sample.txt", "text/plain")

    post dependent_documents_path(@dependent), params: { document: { files: [ upload ] } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_redirected_to dependent_documents_path(@dependent)
    follow_redirect!(headers: { "Accept" => "text/vnd.turbo-stream.html" })

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select "[data-testid='documents-search-form']"
    assert_select "[data-testid='flash-notice']", text: /1 document uploaded and being prepared/
    assert_select "turbo-stream", count: 0
  end

  test "Turbo delete redirect renders the full list and its success message" do
    document = create_document(@dependent, "delete-record.txt", :general)

    delete dependent_documents_path(@dependent), params: { document_selection: [ document.id ], q: "record" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_redirected_to dependent_documents_path(@dependent, q: "record")
    follow_redirect!(headers: { "Accept" => "text/vnd.turbo-stream.html" })

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select "input[data-testid='documents-search-field'][value='record']"
    assert_select "[data-testid='flash-notice']", text: /1 document deleted/
    assert_select "turbo-stream", count: 0
  end

  test "failed document explains that the original is saved without recommending another upload" do
    document = create_document(@dependent, "failed.txt", :general)
    document.failed!

    get document_path(document)

    assert_response :success
    assert_includes response.body, "Your file is saved, but we couldn’t finish processing it. Please contact support."
    assert_not_includes response.body, "Try uploading it again"
  end

  private

    def dom_id(record, prefix)
      ActionView::RecordIdentifier.dom_id(record, prefix)
    end

    def refresh_headers
      { "Accept" => "text/vnd.turbo-stream.html", "X-Document-List-Refresh" => "true" }
    end

    def create_document(dependent, filename, category)
      document = dependent.documents.new(account: dependent.account, user: users(:family_admin), category: category)
      document.file.attach(io: StringIO.new("Synthetic document list update test."), filename: filename, content_type: "text/plain")
      document.tap(&:save!)
    end
end
