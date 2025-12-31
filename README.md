# liquidz

A [Liquid](https://shopify.github.io/liquid/) template engine written in Zig.

## Why

- 💎 **Ruby-only limitation:** Shopify maintains Liquid only in Ruby since they can assume a Ruby runtime on their servers and developers' machines. The rest of us aren't so lucky.
- 🎯 **Universal reach:** A systems language like Zig lets us target every platform: standalone binaries, WebAssembly, and libraries that any runtime can include via foreign function interfaces.
- 🔧 **One implementation to rule them all:** Instead of maintaining separate Liquid parsers for each platform or language, we maintain one battle-tested implementation and build bindings for the rest.

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

## Benchmarks

Liquidz is significantly faster than Ruby Liquid. Benchmarks are measured using [hyperfine](https://github.com/sharkdp/hyperfine) with 1000 render iterations per run.

### Comprehensive Template

A [comprehensive template](benchmark/templates/comprehensive.liquid) that exercises all major Liquid tags and filters against realistic e-commerce data:

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| Liquidz (Zig) | 252.5 ± 81.0 | 204.0 | 529.8 | 1.00 |
| Ruby Liquid | 844.3 ± 52.7 | 797.3 | 978.8 | 3.34 ± 1.09 |

**Liquidz is ~3.3x faster than Ruby Liquid.**

### Shopify Dawn Theme

We also benchmark against real-world templates from [Shopify's Dawn theme](https://github.com/Shopify/dawn). Out of 92 templates, 28 work with Liquidz. The remaining templates use Shopify-specific extensions like `{% form %}`, `{% schema %}`, and Ruby-style method calls (`product.gift_card?`) that are not part of standard Liquid.

| Template | Liquidz [ms] | Ruby [ms] | Speedup |
|:---|---:|---:|---:|
| card-collection.liquid | 12.0 ± 1.1 | 186.7 ± 106.1 | 15.6x |
| facets.liquid | 20.1 ± 1.1 | 171.7 ± 35.6 | 8.5x |
| price.liquid | 37.4 ± 71.1 | 171.5 ± 40.9 | 4.6x |

**On Dawn templates, Liquidz is 5-15x faster than Ruby Liquid.**

### Running Benchmarks

```bash
# Quick benchmark (single template)
./benchmark/run.sh benchmark/templates/comprehensive.liquid 1000

# With hyperfine for statistical rigor
./benchmark/run.sh benchmark/templates/comprehensive.liquid 1000 --hyperfine

# Benchmark all Dawn theme templates
./benchmark/run.sh
```

The benchmark infrastructure is in the [`benchmark/`](benchmark/) directory. It includes:
- `bench.zig` - Zig benchmark runner
- `ruby_bench.rb` - Ruby benchmark runner for comparison
- `run.sh` - Wrapper script for running comparisons
- `templates/comprehensive.liquid` - Comprehensive template using all features
- `themes/dawn/` - Shopify Dawn theme templates
- `shopify_mock_data.json` - Realistic e-commerce data

## License

MIT
