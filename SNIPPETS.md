# Liquidz Usage Examples

Quick examples showing how to use Liquidz in different languages.

## Ruby

```ruby
require 'liquidz'

# Basic variable interpolation
Liquidz.render_string('Hello {{ name }}!', { name: 'World' })
# => "Hello World!"

# Loops
Liquidz.render_string('{% for item in items %}{{ item }} {% endfor %}', { items: ['a', 'b', 'c'] })
# => "a b c "

# Filters
Liquidz.render_string('{{ name | upcase }}', { name: 'hello' })
# => "HELLO"

# Conditionals
Liquidz.render_string('{% if active %}Yes{% else %}No{% endif %}', { active: true })
# => "Yes"
```

## Python

```python
from liquidz import render

# Basic variable interpolation
render('Hello {{ name }}!', {'name': 'World'})
# => "Hello World!"

# Loops
render('{% for item in items %}{{ item }} {% endfor %}', {'items': ['a', 'b', 'c']})
# => "a b c "

# Filters
render('{{ name | upcase }}', {'name': 'hello'})
# => "HELLO"

# Conditionals
render('{% if active %}Yes{% else %}No{% endif %}', {'active': True})
# => "Yes"
```

## Node.js / Browser

The npm package works in both Node.js (using native addon) and browsers (using WASM).

### Node.js (native, synchronous)

```javascript
const { render } = require('liquidz');

// In Node.js with native addon, render works synchronously
render('Hello {{ name }}!', { name: 'World' });
// => "Hello World!"

// Check which backend is being used
const { isNative, isWasm } = require('liquidz');
console.log('Using native:', isNative()); // true in Node.js
console.log('Using WASM:', isWasm());     // false in Node.js
```

### Browser / Universal (async)

```javascript
import { init, render, renderAsync } from 'liquidz';

// Option 1: Initialize first, then render synchronously
await init();
render('Hello {{ name }}!', { name: 'World' });

// Option 2: Use renderAsync (auto-initializes)
await renderAsync('Hello {{ name }}!', { name: 'World' });
// => "Hello World!"

// Loops
await renderAsync('{% for item in items %}{{ item }} {% endfor %}', { items: ['a', 'b', 'c'] });
// => "a b c "

// Filters
await renderAsync('{{ name | upcase }}', { name: 'hello' });
// => "HELLO"

// Conditionals
await renderAsync('{% if active %}Yes{% else %}No{% endif %}', { active: true });
// => "Yes"
```

## Elixir

```elixir
# Basic variable interpolation
Liquidz.render("Hello {{ name }}!", %{name: "World"})
# => {:ok, "Hello World!"}

# Loops
Liquidz.render("{% for item in items %}{{ item }} {% endfor %}", %{items: ["a", "b", "c"]})
# => {:ok, "a b c "}

# Filters
Liquidz.render("{{ name | upcase }}", %{name: "hello"})
# => {:ok, "HELLO"}

# Conditionals
Liquidz.render("{% if active %}Yes{% else %}No{% endif %}", %{active: true})
# => {:ok, "Yes"}
```

## Installation

### Ruby
```bash
gem install liquidz
```

### Python
```bash
pip install liquidz
```

### Node.js
```bash
npm install liquidz
```

### Elixir
```elixir
# In mix.exs
def deps do
  [
    {:liquidz, "~> 0.2"}
  ]
end
```
