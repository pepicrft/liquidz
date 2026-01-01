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

## Node.js

### CommonJS

```javascript
const liquidz = require('liquidz');

// Basic variable interpolation
liquidz.render('Hello {{ name }}!', { name: 'World' });
// => "Hello World!"

// Loops
liquidz.render('{% for item in items %}{{ item }} {% endfor %}', { items: ['a', 'b', 'c'] });
// => "a b c "

// Filters
liquidz.render('{{ name | upcase }}', { name: 'hello' });
// => "HELLO"

// Conditionals
liquidz.render('{% if active %}Yes{% else %}No{% endif %}', { active: true });
// => "Yes"
```

### ESM

```javascript
import { render } from 'liquidz';

// Basic variable interpolation
render('Hello {{ name }}!', { name: 'World' });
// => "Hello World!"

// Loops
render('{% for item in items %}{{ item }} {% endfor %}', { items: ['a', 'b', 'c'] });
// => "a b c "

// Filters
render('{{ name | upcase }}', { name: 'hello' });
// => "HELLO"

// Conditionals
render('{% if active %}Yes{% else %}No{% endif %}', { active: true });
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
