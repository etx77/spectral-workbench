require File.dirname(__FILE__) + '/../test_helper'
require 'capture_controller'

# Re-raise errors caught by the controller.
class CaptureController; def rescue_action(e) raise e end; end

class CaptureControllerTest < ActionController::TestCase

  fixtures :users

  test "should get capture" do
    get :index
    assert_response :success
    assert_not_nil :spectrums
  end

  test "should get capture while logged in" do
    session[:user_id] = users(:quentin).id # log in
    get :index
    assert_response :success
    assert_not_nil :spectrums
    assert_not_nil :calibration
    assert_not_nil :calibrations
  end

end
