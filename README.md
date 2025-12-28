# liquidz 🧪

A fast [Liquid](https://shopify.github.io/liquid/) template engine written in Zig.

## Why Zig? 🦎

Shopify's official Liquid implementation is Ruby-only, limiting adoption in environments where Ruby isn't available or practical. By implementing Liquid in Zig, we unlock:

- **Cross-compilation** 🎯 - Build native binaries for any platform (Linux, macOS, Windows) and architecture (x86_64, ARM, WASM) from a single codebase
- **Zero dependencies** 📦 - No Ruby runtime, no gems, no version conflicts
- **Blazing performance** ⚡ - Native code execution with minimal memory footprint
- **Embeddable** 🔧 - Easy to integrate into any project via CLI, C ABI, or WASM

## Building 🔨

```bash
zig build
```

## Usage 🚀

```bash
./zig-out/bin/liquidz template.liquid '{"name": "World"}'
```

## Testing ✅

```bash
# Run golden tests
ruby test/run_golden_tests.rb

# Run Zig tests
zig build test
```

## License 📄

MIT
