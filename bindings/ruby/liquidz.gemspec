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

  # Check if we have a precompiled extension AND we're building for release (not development)
  precompiled_ext = Dir["lib/liquidz_ext/*.{so,bundle,dll}"]

  if precompiled_ext.any? && ENV["BUILD_NATIVE_GEM"]
    # Native gem with precompiled extension - no compilation needed
    spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
    # Use generic platform without Darwin version for broader compatibility
    current = Gem::Platform.local
    if current.os == "darwin"
      # Use arm64-darwin or x86_64-darwin without version suffix
      spec.platform = Gem::Platform.new("#{current.cpu}-darwin")
    else
      spec.platform = current
    end
  else
    # Source gem - needs compilation
    spec.files = Dir["lib/**/*.rb", "ext/**/*", "README.md", "LICENSE"]
    spec.extensions = ["ext/liquidz_ext/extconf.rb"]
  end

  spec.require_paths = ["lib"]
  spec.add_dependency "json"
end
