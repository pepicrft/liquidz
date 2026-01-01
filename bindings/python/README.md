# Liquidz Python Binding

High-performance Liquid template engine for Python, powered by Zig.

## Installation

```bash
pip install liquidz
```

**Prerequisites:** You need to build the Zig library first:

```bash
cd ../..  # Go to project root
zig build -Doptimize=ReleaseFast
```

## Usage

```python
from liquidz import render

# Simple variable substitution
result = render("Hello, {{ name }}!", {"name": "World"})
print(result)  # "Hello, World!"

# With loops
result = render("{% for item in items %}{{ item }} {% endfor %}", {"items": ["a", "b", "c"]})
print(result)  # "a b c "

# With conditionals
result = render("{% if show %}visible{% endif %}", {"show": True})
print(result)  # "visible"

# With filters
result = render("{{ name | upcase }}", {"name": "hello"})
print(result)  # "HELLO"

# Using JSON string directly
result = render("{{ x }}", '{"x": 42}')
print(result)  # "42"

# Empty data (defaults to {})
result = render("Hello")
print(result)  # "Hello"
```

## API

### `render(template, data=None)`

Renders a Liquid template with the given data.

**Parameters:**
- `template` (str): The Liquid template string
- `data` (dict | str | None): The data to render with. Can be a dict or a JSON string. Defaults to `None` (empty dict).

**Returns:**
- `str`: The rendered template

**Raises:**
- `RenderError`: If rendering fails
- `LiquidzError`: If the library cannot be loaded

### `render_string(template, data=None)`

Alias for `render()`.

### Exceptions

- `LiquidzError`: Base exception for all Liquidz errors
- `RenderError`: Raised when template rendering fails

## Running Tests

```bash
pip install pytest
pytest
```

## License

MIT
