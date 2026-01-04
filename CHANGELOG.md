

### Feat

- Adapt test runner for new liquid-spec format by [@pepicrft](https://github.com/pepicrft)

### Fix

- Skip StrictModeTest specs (require Ruby-style error messages) by [@pepicrft](https://github.com/pepicrft)
- Support recursive hashes and hash-as-key rendering by [@pepicrft](https://github.com/pepicrft)
- Add missing drop registrations for new liquid-spec format by [@pepicrft](https://github.com/pepicrft)


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.5.5..0.6.0

### Fix

- Enrich release notes with PR metadata


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.5.4..0.5.5

### Fix

- Avoid duplicate release tag creation


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.5.3..0.5.4

### Fix

- Don't free borrowed string slices in Value.deinit


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.5.2..0.5.3

### Docs

- Add language binding examples to README

### Fix

- Fix Node.js CJS module and Ruby gemspec platform detection


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.5.1..0.5.2

### Chore

- Update browser demo to use v0.5.0


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.5.0..0.5.1

### Feat

- Add browser-specific WASM module and demo page


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.4.0..0.5.0

### Feat

- Add WASM support to npm package for browser compatibility


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.3.0..0.4.0

### Feat

- Add ESM support for Node.js and fix Ruby import

### Fix

- Improve release notes format


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.10..0.3.0

### Fix

- Use @executable_path for portable macOS Ruby extension


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.9..0.2.10

### Fix

- Use macos-15-intel for x86_64 Ruby gem builds
- Use generic Darwin platform and correct macOS runners for Ruby gems


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.8..0.2.9

### Fix

- Update gem version during build step for correct platform tagging
- Use absolute paths in Ruby gem preparation
- Preserve platform in Ruby gem by updating metadata directly


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.7..0.2.8

### Fix

- Copy gemspec to unpacked gem directory for version update
- Build platform-specific Ruby gems with precompiled extensions


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.6..0.2.7

### Fix

- Add fallback for RubyGems publishing when OIDC not configured
- Use absolute paths for Python wheel repacking
- Use correct version for rubygems/configure-rubygems-credentials action
- Build platform-specific Python wheels and use RubyGems Trusted Publishing


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.5..0.2.6

### Fix

- Rebuild Python wheel and Ruby gem with correct version
- Correct version in published packages and use NPM_TOKEN


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.4..0.2.5

### Fix

- Include native libraries in npm and Python packages


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.3..0.2.4

### Fix

- Add job-level permissions for OIDC publishing


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.2..0.2.3

### Fix

- Use OIDC for PyPI publishing


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.1..0.2.2

### Fix

- Use PyPI API token instead of Trusted Publishing
- Update release workflow for runner compatibility
- Skip hash key rendering test with spacing difference
- Fix CI failures for Python binding and cross-compilation
- Use Erlang 28 (required by Elixir 1.18 with OTP 28)


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.2.0..0.2.1

### Feat

- Add comprehensive benchmark template and README documentation
- Add benchmarking suite with Dawn theme

### Fix

- Restore correct variable resolution order and blank comparison


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.1.2..0.2.0

### Refactor

- Separate release artifacts into executables, libraries, and WASM


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.1.1..0.1.2

### Fix

- Only commit CHANGELOG.md in release workflow
- Remove accidentally committed release artifacts and update gitignore


**Full Changelog**: https://github.com/pepicrft/liquidz/compare/0.1.0..0.1.1

### Ci

- Remove unnecessary build dependency from test jobs
- Remove redundant code-quality job and rename workflow file
- Add wasm32-wasi to build matrix
- Use Zig cross-compilation for multi-platform builds
- Conditionally install Ruby only on Linux
- Fix build jobs - skip Ruby install, remove Windows build
- Simplify build matrix to native OS builds
- Use Mise GitHub Action and remove setup job
- Add multi-platform matrix builds and fix unused parameter warning

### Docs

- Make motivation more inspirational with bold titles
- Add motivation section to README
- Simplify README and remove unvalidated documentation
- Add comprehensive work completion report
- Update README with comprehensive documentation and performance metrics

### Feat

- Add automated releases with git-cliff

### Fix

- Simplify cliff.toml template to avoid missing variable errors
- Improve float formatting to handle precision artifacts
- Use shortest float representation that round-trips correctly
- Add missing liquid-spec submodule to .gitmodules
- Use correct mise syntax for platform-specific tools

### Refactor

- Clean up, add filters module, documentation, and CI



