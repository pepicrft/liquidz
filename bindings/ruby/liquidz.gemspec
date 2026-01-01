# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "liquidz"
  spec.version       = "0.2.7"
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

  # Check if we have a precompiled extension
  precompiled_ext = Dir["lib/liquidz_ext/*.{so,bundle,dll}"]

  if precompiled_ext.any? && !ENV["FORCE_SOURCE_BUILD"]
    # Native gem with precompiled extension - no compilation needed
    spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
    spec.platform = Gem::Platform::CURRENT
  else
    # Source gem - needs compilation
    spec.files = Dir["lib/**/*.rb", "ext/**/*", "README.md", "LICENSE"]
    spec.extensions = ["ext/liquidz_ext/extconf.rb"]
  end

  spec.require_paths = ["lib"]
  spec.add_dependency "json"
end
