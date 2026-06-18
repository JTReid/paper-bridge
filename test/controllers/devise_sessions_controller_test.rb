require "test_helper"

class DeviseSessionsControllerTest < ActionDispatch::IntegrationTest
  test "shows styled sign in form" do
    get new_user_session_path

    assert_response :success
    assert_select "h1", "Sign in"
    assert_select "form[action='#{user_session_path}']" do
      assert_select "input[name='user[email]']"
      assert_select "input[name='user[password]']"
      assert_select "input[name='user[remember_me]']"
      assert_select "input[type='submit'][value='Sign in']"
    end
    assert_select "a[href='#{new_user_registration_path}']", "Create one"
    assert_select "a[href='#{new_user_password_path}']", "Forgot your password?"
  end
end
