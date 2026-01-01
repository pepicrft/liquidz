# Liquidz

High-performance Liquid template engine for Elixir, powered by Zig.

## Installation

Add `liquidz` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:liquidz, "~> 0.2.0"}
  ]
end
```

**Prerequisites:** You need to build the Zig library first:

```bash
cd ../..  # Go to project root
zig build -Doptimize=ReleaseFast
```

## Usage

```elixir
# Simple variable substitution
{:ok, result} = Liquidz.render("Hello, {{ name }}!", %{name: "World"})
# => "Hello, World!"

# Using the bang version (raises on error)
result = Liquidz.render!("Hello, {{ name }}!", %{name: "World"})
# => "Hello, World!"

# With loops
result = Liquidz.render!("{% for item in items %}{{ item }} {% endfor %}", %{items: ["a", "b", "c"]})
# => "a b c "

# With conditionals
result = Liquidz.render!("{% if show %}visible{% endif %}", %{show: true})
# => "visible"

# With filters
result = Liquidz.render!("{{ name | upcase }}", %{name: "hello"})
# => "HELLO"

# Using keyword lists
result = Liquidz.render!("{{ name }}", name: "World")
# => "World"

# Using JSON string directly
result = Liquidz.render!("{{ x }}", ~s({"x": 42}))
# => "42"
```

## API

### `Liquidz.render(template, data \\ %{})`

Renders a Liquid template with the given data. Returns `{:ok, result}` or `{:error, reason}`.

### `Liquidz.render!(template, data \\ %{})`

Same as `render/2` but raises on error.

### `Liquidz.render_string/2` and `Liquidz.render_string!/2`

Aliases for `render/2` and `render!/2`.

## Running Tests

```bash
mix deps.get
mix test
```

## License

MIT
