# frozen_string_literal: true

require_relative "lib/bt_fake/version"

Gem::Specification.new do |spec|
  spec.name = "bt-fake"
  spec.version = BtFake::VERSION
  spec.authors = ["Braintrust"]
  spec.email = ["info@braintrust.dev"]
  spec.summary = "Braintrust dummy gem for testing purposes."
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir.glob("lib/**/*.rb")
  spec.require_paths = ["lib"]
end
