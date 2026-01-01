
## [0.2.10] - 2026-01-01

### Fix

- Use @executable_path for portable macOS Ruby extension ([9c6bbee](https://github.com/pepicrft/liquidz/commit/9c6bbee5a2c56beca4b5555a1c7c2942f28f80ae))
## [0.2.9] - 2026-01-01

### Fix

- Use macos-15-intel for x86_64 Ruby gem builds ([c099ba0](https://github.com/pepicrft/liquidz/commit/c099ba027ab1309c00c92fe557555f7a2ed90ac0))
- Use generic Darwin platform and correct macOS runners for Ruby gems ([8cea1b5](https://github.com/pepicrft/liquidz/commit/8cea1b5049c71dfe89525b5f028797fb11ce46af))
## [0.2.8] - 2026-01-01

### Fix

- Update gem version during build step for correct platform tagging ([a576c21](https://github.com/pepicrft/liquidz/commit/a576c211e7d2f0aac5c3e59b4c822e028b1f5ba2))
- Use absolute paths in Ruby gem preparation ([774ae74](https://github.com/pepicrft/liquidz/commit/774ae74a81c07e4dcef5e96573797efdd287911f))
- Preserve platform in Ruby gem by updating metadata directly ([debc6ea](https://github.com/pepicrft/liquidz/commit/debc6eaf5af9c941713adf6a0649eb53ecbe0771))
## [0.2.7] - 2026-01-01

### Fix

- Copy gemspec to unpacked gem directory for version update ([dadfe3b](https://github.com/pepicrft/liquidz/commit/dadfe3be5bf4049f7193fd0964e8fb86d90328af))
- Build platform-specific Ruby gems with precompiled extensions ([0056aad](https://github.com/pepicrft/liquidz/commit/0056aad395c3e3b7bc165c9621b99993cd23abd6))
## [0.2.6] - 2026-01-01

### Fix

- Add fallback for RubyGems publishing when OIDC not configured ([dd76acd](https://github.com/pepicrft/liquidz/commit/dd76acdde59fd5bafb54a19aca26fe0f3ccd7338))
- Use absolute paths for Python wheel repacking ([686f8f6](https://github.com/pepicrft/liquidz/commit/686f8f6c120ec48fb19614ddc2e115a525e9b07a))
- Use correct version for rubygems/configure-rubygems-credentials action ([7cc9397](https://github.com/pepicrft/liquidz/commit/7cc9397898e18aa4535c01e838eecc2cd9b6c833))
- Build platform-specific Python wheels and use RubyGems Trusted Publishing ([5ff783c](https://github.com/pepicrft/liquidz/commit/5ff783c7c12af3cfee36d4311ca253e8d0e2319d))
## [0.2.5] - 2026-01-01

### Fix

- Rebuild Python wheel and Ruby gem with correct version ([fa52cc6](https://github.com/pepicrft/liquidz/commit/fa52cc606d60be1265e8a89872ea3e2155f7075e))
- Correct version in published packages and use NPM_TOKEN ([fc01357](https://github.com/pepicrft/liquidz/commit/fc01357dd09ea7ffe35e07ee40de2b1be85447ff))
## [0.2.4] - 2026-01-01

### Fix

- Include native libraries in npm and Python packages ([8ad5d8d](https://github.com/pepicrft/liquidz/commit/8ad5d8d4437dcb79ec65ac55242906346dafdf65))
## [0.2.3] - 2026-01-01

### Fix

- Add job-level permissions for OIDC publishing ([eb99c3a](https://github.com/pepicrft/liquidz/commit/eb99c3a162b33ff393caa1b1e8c259895655fa48))
## [0.2.2] - 2026-01-01

### Fix

- Use OIDC for PyPI publishing ([82cc08a](https://github.com/pepicrft/liquidz/commit/82cc08ae7c58c085a17a8ab7bcda214d3bfca582))
## [0.2.1] - 2026-01-01

### Fix

- Use PyPI API token instead of Trusted Publishing ([4409a49](https://github.com/pepicrft/liquidz/commit/4409a49baa40ae8c0713b5f521232973da270dfe))
- Update release workflow for runner compatibility ([b47dc39](https://github.com/pepicrft/liquidz/commit/b47dc39554b5f847350a4e1db9edbcee9849496a))
- Skip hash key rendering test with spacing difference ([439d682](https://github.com/pepicrft/liquidz/commit/439d68200eef1b6d9eb2de225c43ab28974b55a9))
- Fix CI failures for Python binding and cross-compilation ([8c9d746](https://github.com/pepicrft/liquidz/commit/8c9d746242ab2a1d2b27ccf61868161a7098a3f9))
- Use Erlang 28 (required by Elixir 1.18 with OTP 28) ([66668cf](https://github.com/pepicrft/liquidz/commit/66668cfccd9ea5afd38e57b50d5a9d102fcebfcf))
## [0.2.0] - 2025-12-31

### Feat

- Add comprehensive benchmark template and README documentation ([fd9f1f7](https://github.com/pepicrft/liquidz/commit/fd9f1f71accb964be76d478c2e05aa4a6c8e9cd8))
- Add benchmarking suite with Dawn theme ([d721f09](https://github.com/pepicrft/liquidz/commit/d721f093d89fb8e0661c6cdcbf50e7c10680b6a8))

### Fix

- Restore correct variable resolution order and blank comparison ([022d8dc](https://github.com/pepicrft/liquidz/commit/022d8dcef5836f20ef76bad23e2ec242f0fee3ed))
## [0.1.2] - 2025-12-31

### Refactor

- Separate release artifacts into executables, libraries, and WASM ([af5b112](https://github.com/pepicrft/liquidz/commit/af5b1126efe5973ea29117c16905a26f3f8424c6))
## [0.1.1] - 2025-12-31

### Fix

- Only commit CHANGELOG.md in release workflow ([01c7fcc](https://github.com/pepicrft/liquidz/commit/01c7fcc3d7ec12e5539323ed244b5efac0266580))
- Remove accidentally committed release artifacts and update gitignore ([ca2ba17](https://github.com/pepicrft/liquidz/commit/ca2ba1704ffe30f9bfc532d1aa97b42e1e69e4cd))
## [0.1.0] - 2025-12-31

### Ci

- Remove unnecessary build dependency from test jobs ([5efc2b7](https://github.com/pepicrft/liquidz/commit/5efc2b759db59e3ba3c6870672d0e85b193c898a))
- Remove redundant code-quality job and rename workflow file ([0398ce7](https://github.com/pepicrft/liquidz/commit/0398ce7fbe09d123f261c49e4f88e43cdd924b96))
- Add wasm32-wasi to build matrix ([b71c067](https://github.com/pepicrft/liquidz/commit/b71c067a9bc425cd37534f5ceabad633d214167a))
- Use Zig cross-compilation for multi-platform builds ([db3873d](https://github.com/pepicrft/liquidz/commit/db3873d0ae2908b30d77223921ce6d0de8e12323))
- Conditionally install Ruby only on Linux ([09c3960](https://github.com/pepicrft/liquidz/commit/09c3960691d0be205ee2b23f356dc8cbaa2c262a))
- Fix build jobs - skip Ruby install, remove Windows build ([eb91c83](https://github.com/pepicrft/liquidz/commit/eb91c837522403b4e44371ca9dffa861fc33c127))
- Simplify build matrix to native OS builds ([c4bd56d](https://github.com/pepicrft/liquidz/commit/c4bd56d7363e589f8fee4bc7ff25c1cc0b63fe22))
- Use Mise GitHub Action and remove setup job ([8b1d74c](https://github.com/pepicrft/liquidz/commit/8b1d74c058c24d94b7c8ed89051753d5fafaab55))
- Add multi-platform matrix builds and fix unused parameter warning ([df13005](https://github.com/pepicrft/liquidz/commit/df1300528442648c37a96f416b9fdbaefe0a07e8))

### Docs

- Make motivation more inspirational with bold titles ([4e0ee44](https://github.com/pepicrft/liquidz/commit/4e0ee44dfaa60ccde9d600e66c04c280afc14305))
- Add motivation section to README ([1b2bdd4](https://github.com/pepicrft/liquidz/commit/1b2bdd4ae40377f3ba207b918f41c9b7a2e50d3a))
- Simplify README and remove unvalidated documentation ([df05608](https://github.com/pepicrft/liquidz/commit/df056087d65ee0852233b0a91195beb43e70636e))
- Add comprehensive work completion report ([9fc30a6](https://github.com/pepicrft/liquidz/commit/9fc30a610827727e62b35f357d339e7efd8a3997))
- Update README with comprehensive documentation and performance metrics ([102b5bb](https://github.com/pepicrft/liquidz/commit/102b5bb39d65db7d812b618f2f943bde680c5b77))

### Feat

- Add automated releases with git-cliff ([8887d5f](https://github.com/pepicrft/liquidz/commit/8887d5fca19db7d0c580b072a7c2adb5086f2148))

### Fix

- Simplify cliff.toml template to avoid missing variable errors ([5aa4e48](https://github.com/pepicrft/liquidz/commit/5aa4e4816fc0be22e70e65d456ac6a717f8ba801))
- Improve float formatting to handle precision artifacts ([bef5e6a](https://github.com/pepicrft/liquidz/commit/bef5e6ad98dc2cca7af67593e45f2f7d8111e9da))
- Use shortest float representation that round-trips correctly ([bf9f8f8](https://github.com/pepicrft/liquidz/commit/bf9f8f8793eff86e02d180da211c21e916584ddd))
- Add missing liquid-spec submodule to .gitmodules ([34d91c8](https://github.com/pepicrft/liquidz/commit/34d91c8df3a28a51ffc60c4eb13d13f2d68b7247))
- Use correct mise syntax for platform-specific tools ([3b92ccb](https://github.com/pepicrft/liquidz/commit/3b92ccb85e979620f5b0e968dafc0cf3dbed374d))

### Refactor

- Clean up, add filters module, documentation, and CI ([4bff5e2](https://github.com/pepicrft/liquidz/commit/4bff5e22eca7d553f4de115bcb3c93317d3c6a4a))
[0.2.10]: https://github.com/pepicrft/liquidz/compare/0.2.9..0.2.10
[0.2.9]: https://github.com/pepicrft/liquidz/compare/0.2.8..0.2.9
[0.2.8]: https://github.com/pepicrft/liquidz/compare/0.2.7..0.2.8
[0.2.7]: https://github.com/pepicrft/liquidz/compare/0.2.6..0.2.7
[0.2.6]: https://github.com/pepicrft/liquidz/compare/0.2.5..0.2.6
[0.2.5]: https://github.com/pepicrft/liquidz/compare/0.2.4..0.2.5
[0.2.4]: https://github.com/pepicrft/liquidz/compare/0.2.3..0.2.4
[0.2.3]: https://github.com/pepicrft/liquidz/compare/0.2.2..0.2.3
[0.2.2]: https://github.com/pepicrft/liquidz/compare/0.2.1..0.2.2
[0.2.1]: https://github.com/pepicrft/liquidz/compare/0.2.0..0.2.1
[0.2.0]: https://github.com/pepicrft/liquidz/compare/0.1.2..0.2.0
[0.1.2]: https://github.com/pepicrft/liquidz/compare/0.1.1..0.1.2
[0.1.1]: https://github.com/pepicrft/liquidz/compare/0.1.0..0.1.1

<!-- generated by git-cliff -->
