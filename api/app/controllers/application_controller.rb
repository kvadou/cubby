class ApplicationController < ActionController::API
  include ActionController::Cookies
  # Order matters: the origin check runs before authentication, so a forged request learns nothing.
  include SameOriginRequests
  include Authentication
end
