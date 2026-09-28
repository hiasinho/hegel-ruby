# frozen_string_literal: true

require_relative "lib/hegel/version"

Gem::Specification.new do |spec|
  spec.name = "hegel-ruby"
  spec.version = Hegel::VERSION
  spec.authors = [ "Hegel Ruby contributors" ]
  spec.summary = "A Ruby frontend for the Hegel property-based testing engine"
  spec.description = "A minimal Ruby frontend for generation, shrinking, and replay with libhegel."
  spec.homepage = "https://hegel.dev/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir[ "lib/**/*.rb", "README.md", "LICENSE" ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "ffi", "~> 1.17"
end
