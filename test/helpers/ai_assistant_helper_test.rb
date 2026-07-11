require "test_helper"

class AiAssistantHelperTest < ActionView::TestCase
  test "renders escaped answer text with PDF source links at cited pages" do
    document = documents(:advance_directive)
    attach_pdf(document)
    citation = {
      source_number: 1,
      document_id: document.id,
      document_title: document.title,
      page_number: 4,
      quote: "Source text"
    }

    html = ai_answer_with_source_links(
      "Supported <script>alert('no')</script> [1]. Unknown [9].",
      citations: [ citation ],
      documents_by_id: { document.id => document }
    )
    fragment = Nokogiri::HTML.fragment(html)
    link = fragment.at_css("a[data-testid='ai-inline-source-1']")

    assert_equal "[1]", link.text
    assert_equal original_document_path(document, page: 4), link["href"]
    assert_equal "_blank", link["target"]
    assert_equal "noopener", link["rel"]
    assert_includes link["aria-label"], "#{document.title}, page 4"
    assert_includes fragment.to_html, "&lt;script&gt;"
    assert_not_includes fragment.text, "[9]"
  end

  test "renders multiple source links for distinct cited pages" do
    document = documents(:advance_directive)
    attach_pdf(document)
    citations = [
      { source_number: 1, document_id: document.id, document_title: document.title, page_number: 2 },
      { source_number: 2, document_id: document.id, document_title: document.title, page_number: 5 }
    ]

    html = ai_answer_with_source_links(
      "The answer uses two pages [1, 2].",
      citations: citations,
      documents_by_id: { document.id => document }
    )
    fragment = Nokogiri::HTML.fragment(html)

    assert_equal "The answer uses two pages [1] [2].", fragment.text
    assert_equal original_document_path(document, page: 2), fragment.at_css("[data-testid='ai-inline-source-1']")["href"]
    assert_equal original_document_path(document, page: 5), fragment.at_css("[data-testid='ai-inline-source-2']")["href"]
  end

  test "renders a missing or hostile source as escaped text without a link" do
    document = documents(:advance_directive)
    citation = {
      source_number: 1,
      document_id: -1,
      document_title: "<img src=x onerror=alert(1)>",
      page_number: 1
    }

    html = safe_join([ ai_source_link(citation, documents_by_id: {}) ])
    fragment = Nokogiri::HTML.fragment(html)

    assert_empty fragment.css("a")
    assert_empty fragment.css("img")
    assert_equal "<img src=x onerror=alert(1)>, page 1", fragment.text

    linked_html = ai_source_link(citation.merge(document_id: document.id), documents_by_id: { document.id => document })
    linked_fragment = Nokogiri::HTML.fragment(linked_html)

    assert_equal 1, linked_fragment.css("a").size
    assert_empty linked_fragment.css("img")
    assert_equal "<img src=x onerror=alert(1)>, page 1", linked_fragment.text
  end

  test "links non-PDF sources to the authorized document page" do
    document = documents(:advance_directive)
    citation = {
      source_number: 1,
      document_id: document.id,
      document_title: document.title,
      page_number: 1,
      quote: "Source text"
    }

    html = ai_source_link(citation, documents_by_id: { document.id => document }, testid: "source")
    link = Nokogiri::HTML.fragment(html).at_css("a[data-testid='source']")

    assert_equal document_path(document), link["href"]
    assert_equal "#{document.title}, page 1", link.text
  end

  private

    def attach_pdf(document)
      document.file.attach(
        io: StringIO.new("%PDF-1.4\n% fake test pdf"),
        filename: "advance-directive.pdf",
        content_type: "application/pdf"
      )
      document.update!(original_filename: "advance-directive.pdf", content_type: "application/pdf")
    end
end
