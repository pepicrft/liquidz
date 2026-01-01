# Liquidz Language Bindings

This directory contains language bindings for the Liquidz Liquid template engine.

## Available Bindings

| Language | Directory | Status | Notes |
|----------|-----------|--------|-------|
| Node.js / Bun / Deno | `nodejs/` | Ready | N-API based, works with all JS runtimes |
| Elixir | `elixir/` | Ready | NIF-based using elixir_make |
| Ruby | `ruby/` | Ready | C extension |
| Python | `python/` | Ready | ctypes-based FFI |

## Prerequisites

Before using any binding, you must build the Zig library:

```bash
# From the project root
zig build -Doptimize=ReleaseFast
```

This will generate:
- `zig-out/lib/libliquidz_ffi.a` - Static library for Node.js, Ruby, Elixir
- `zig-out/lib/libliquidz_ffi.dylib` (macOS) / `.so` (Linux) / `.dll` (Windows) - Dynamic library for Python, Deno

## Quick Start

### Node.js / Bun / Deno

```bash
cd bindings/nodejs
npm install
npm test
```

```javascript
const { render } = require('liquidz');
console.log(render('Hello, {{ name }}!', { name: 'World' }));
```

Bun and Deno can use the same binding via their Node.js compatibility layers.

### Elixir

```bash
cd bindings/elixir
mix deps.get
mix test
```

```elixir
Liquidz.render!("Hello, {{ name }}!", %{name: "World"})
```

### Ruby

```bash
cd bindings/ruby
bundle install
bundle exec rake compile
bundle exec ruby -I lib -e 'require "liquidz_ext"; puts Liquidz.render("Hello, {{ name }}!", {name: "World"})'
```

### Python

```bash
cd bindings/python
pip install -e .
pytest
```

```python
from liquidz import render
print(render("Hello, {{ name }}!", {"name": "World"}))
```

## API Summary

All bindings provide the same core API:

### `render(template, data)`

Renders a Liquid template with the given data.

- `template` - The Liquid template string
- `data` - The context data (object/dict/map or JSON string)

Returns the rendered template as a string.

### `render_string(template, data)`

Alias for `render()`.

## Supported Liquid Features

- Variables: `{{ variable }}`
- Filters: `{{ name | upcase | truncate: 10 }}`
- Tags: `if`, `unless`, `case`, `for`, `tablerow`, `assign`, `capture`, `increment`, `decrement`, `cycle`, `include`, `render`, `raw`, `comment`, `liquid`, `echo`
- 50+ built-in filters

See the main README for the complete feature list.

## Performance

Liquidz is approximately 3.3x faster than the Ruby Liquid gem for typical templates, with similar performance gains in other languages due to the Zig core.

## License

MIT
