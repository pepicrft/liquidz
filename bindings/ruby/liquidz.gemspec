# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "liquidz"
  spec.version       = "0.2.2"
  spec.authors       = ["Pedro Pinera Buendia"]
  spec.email         = ["pedro@ppinera.es"]

  spec.summary       = "High-performance Liquid template engine powered by Zig"
  spec.description   = "A fast, drop-in replacement for the Liquid template engine, " \
                       "compiled from Zig to native code for maximum performance."
  spec.homepage      = "https://github.com/pepicrft/liquidz"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files         = Dir["lib/**/*", "ext/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
  spec.extensions    = ["ext/liquidz_ext/extconf.rb"]

  spec.add_dependency "json"
end
