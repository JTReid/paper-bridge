require "test_helper"

class StorageAccessTest < ActionDispatch::IntegrationTest
  test "anonymous visitors cannot create direct uploads even with a valid CSRF token" do
    assert_direct_upload_disabled
  end

  test "signed in users also upload only through the application" do
    sign_in users(:family_admin)

    assert_direct_upload_disabled
  end

  test "permanent blob links cannot bypass the application's file access controls" do
    blob = attach_document.file.blob

    [ "blobs", "blobs/redirect", "blobs/proxy" ].each do |route|
      get "#{ActiveStorage.routes_prefix}/#{route}/#{blob.signed_id}/#{blob.filename}",
        env: { "action_dispatch.show_exceptions" => :all }

      assert_response :not_found
    end
  end

  test "disk uploads have no route" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("#{ActiveStorage.routes_prefix}/disk/upload-token", method: :put)
    end
  end

  test "authorized disk download URLs expire after five minutes" do
    url = authorized_download_url
    sign_out :user

    get url
    assert_response :success
    assert_equal "Private document contents.", response.body

    travel 6.minutes do
      get url

      assert_response :not_found
    end
  end

  test "disk downloads reject a modified signature" do
    url = authorized_download_url
    url.sub!(%r{(/disk/)[^/]+/}, '\1invalid-signature/')
    sign_out :user

    get url

    assert_response :not_found
  end

  private

    def assert_direct_upload_disabled
      previous_forgery_protection = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true

      get root_path
      csrf_token = response.parsed_body.at_css("meta[name='csrf-token']")&.[]("content")
      assert csrf_token.present?, "The request must have a valid CSRF token, as a visitor can obtain one."

      assert_no_difference "ActiveStorage::Blob.count" do
        post "#{ActiveStorage.routes_prefix}/direct_uploads",
          params: {
            blob: {
              filename: "unattached.txt",
              content_type: "text/plain",
              byte_size: 3,
              checksum: Digest::MD5.base64digest("abc")
            }
          },
          headers: { "X-CSRF-Token" => csrf_token },
          env: { "action_dispatch.show_exceptions" => :all },
          as: :json

        assert_response :not_found
      end
    ensure
      ActionController::Base.allow_forgery_protection = previous_forgery_protection
    end

    def attach_document
      document = documents(:advance_directive)
      document.file.attach(io: StringIO.new("Private document contents."), filename: "private.txt", content_type: "text/plain")
      document
    end

    def authorized_download_url
      document = attach_document
      sign_in users(:family_admin)

      get original_document_path(document)

      assert_response :redirect
      response.location
    end
end
