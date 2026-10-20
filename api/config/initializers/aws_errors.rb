# AWS failures that mean "try again later": service errors, missing credentials, timeouts, and resets.
AWS_TRANSIENT_ERRORS = [
  Aws::Errors::ServiceError, Aws::Errors::MissingCredentialsError, Seahorse::Client::NetworkingError
].freeze
