# Liquidz Benchmarks

Benchmarks comparing Liquidz (Zig) vs Ruby Liquid performance using real Shopify themes.

## Running Benchmarks

```bash
# Run all benchmarks (requires Ruby with liquid gem)
./run.sh

# Run specific template
./run.sh themes/dawn/snippets/header-dropdown-menu.liquid

# Run with custom iterations
./run.sh themes/dawn/snippets/card-product.liquid 1000
```

## Requirements

- Zig 0.15+
- Ruby 3.x with `liquid` gem (`gem install liquid`)
- `gdate` (macOS: `brew install coreutils`) or GNU `date`
- `bc` for calculations

## Theme

Uses Shopify's **Dawn** theme (92 templates, ~23k lines of Liquid code) for realistic benchmarks.

## Mock Data

`shopify_mock_data.json` contains mock Shopify objects:
- `shop`, `settings`, `cart`, `customer`
- `product`, `collection`, `collections`
- `section`, `page`, `blog`, `article`
- `localization`, `request`, `routes`

## Shopify Filter Support

Liquidz includes mock implementations of Shopify-specific filters for benchmarking:
- `t` (translation), `asset_url`, `image_url`
- `money`, `money_with_currency`
- `stylesheet_tag`, `script_tag`
- `inline_asset_content`, `placeholder_svg_tag`
- And more...
