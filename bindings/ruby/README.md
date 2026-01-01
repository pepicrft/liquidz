# Liquidz Ruby Binding

High-performance Liquid template engine for Ruby, powered by Zig.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'liquidz'
```

And then execute:

```bash
bundle install
```

Or install it yourself:

```bash
gem install liquidz
```

**Prerequisites:** You need to build the Zig library first:

```bash
zig build -Doptimize=ReleaseFast
```

Then build the gem extension:

```bash
cd ext/liquidz_ext
ruby extconf.rb
make
```

## Usage

```ruby
require 'liquidz_ext'

# Simple variable substitution
result = Liquidz.render("Hello, {{ name }}!", { name: "World" })
# => "Hello, World!"

# With loops
result = Liquidz.render("{% for item in items %}{{ item }} {% endfor %}", { items: ["a", "b", "c"] })
# => "a b c "

# With conditionals
result = Liquidz.render("{% if show %}visible{% endif %}", { show: true })
# => "visible"

# With filters
result = Liquidz.render("{{ name | upcase }}", { name: "hello" })
# => "HELLO"

# Using JSON string directly
result = Liquidz.render("{{ x }}", '{"x": 42}')
# => "42"
```

## Drop-in Replacement for Liquid

Liquidz can act as a drop-in replacement for the standard Liquid gem:

```ruby
require 'liquidz_ext/liquid_patch'

# Now Liquid::Template.parse uses Liquidz under the hood
template = Liquid::Template.parse("Hello, {{ name }}!")
result = template.render({ "name" => "World" })
# => "Hello, World!"
```

## API

### `Liquidz.render(template, data = nil)`

Renders a Liquid template with the given data.

- `template` (String): The Liquid template string
- `data` (Hash, String, nil): The data to render with. Can be a Hash or a JSON string. Defaults to `nil`.

Returns the rendered template as a String.

Raises `RuntimeError` if rendering fails.

### `Liquidz.render_string(template, data = nil)`

Alias for `Liquidz.render`.

## Performance

Liquidz is approximately 3.3x faster than the standard Ruby Liquid gem for typical templates.

## License

MIT
