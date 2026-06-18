# frozen_string_literal: true

require_relative "lib/bt_publishing_test/version"

Gem::Specification.new do |spec|
  spec.name = "bt-publishing-test"
  spec.version = BtPublishingTest::VERSION
  spec.authors = ["Braintrust"]
  spec.email = ["info@braintrust.dev"]
  spec.summary = "Braintrust test package. Used only to validate release workflows end-to-end. Not a real package; do not use."
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir.glob("lib/**/*.rb")
  spec.require_paths = ["lib"]

  # Mirrors real SDK gemspecs that depend on openssl. Keeps the lockfile pinned
  # to the runner's default gem version so the RUBYOPT activation test in
  # validate-ruby remains meaningful as Ruby versions change.
  spec.add_runtime_dependency "openssl", ">= 3.3.1", "< 5.0"
end
