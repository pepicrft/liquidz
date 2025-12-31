# liquidz

A [Liquid](https://shopify.github.io/liquid/) template engine written in Zig.

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
