# liquidz

A [Liquid](https://shopify.github.io/liquid/) template engine written in Zig.

## Why

- 💎 Shopify maintains Liquid only in Ruby since they can assume a Ruby runtime on their servers and developers' machines
- 🎯 A systems language like Zig lets us target many platforms, both as a standalone binary and as a library that other runtimes can include via foreign function interfaces
- 🔧 Instead of maintaining separate Liquid parsers for each platform or language, we maintain one implementation and build the necessary bindings

## Usage

```bash
# Build
zig build

# Render template
./zig-out/bin/liquidz template.liquid '{"name": "World"}'
```

## Testing

```bash
# Unit tests
zig build test

# Golden Liquid tests
cd test && ruby run_golden_tests.rb

# Liquid Spec tests
cd test && ruby run_liquid_spec_tests.rb
```

## License

MIT
