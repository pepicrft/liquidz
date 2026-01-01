# Liquidz JavaScript Binding

High-performance Liquid template engine for Node.js, Bun, and Deno, powered by Zig.

## Installation

```bash
npm install liquidz
```

**Prerequisites:** You need to build the Zig library first:

```bash
cd ../..  # Go to project root
zig build -Doptimize=ReleaseFast
```

## Usage

```javascript
const { render } = require('liquidz');

// Simple variable substitution
const result = render('Hello, {{ name }}!', { name: 'World' });
console.log(result); // "Hello, World!"

// With loops
const list = render('{% for item in items %}{{ item }} {% endfor %}', {
  items: ['a', 'b', 'c']
});
console.log(list); // "a b c "

// With conditionals
const conditional = render('{% if show %}visible{% endif %}', { show: true });
console.log(conditional); // "visible"

// With filters
const filtered = render('{{ name | upcase }}', { name: 'hello' });
console.log(filtered); // "HELLO"

// Using JSON string directly
const fromJson = render('{{ x }}', '{"x": 42}');
console.log(fromJson); // "42"
```

## API

### `render(template, data?)`

Renders a Liquid template with the given data.

- `template` (string): The Liquid template string
- `data` (object | string, optional): The data to render with. Can be a JavaScript object or a JSON string. Defaults to `{}`.

Returns the rendered template as a string.

Throws an error if rendering fails.

### `renderString(template, data?)`

Alias for `render()`.

## Runtime Compatibility

This binding works with multiple JavaScript runtimes:

### Bun

```bash
bun run test.js
```

### Deno

```bash
deno run --allow-ffi --allow-read test.js
```

Note: Deno requires the `--allow-ffi` flag for native modules.

## License

MIT
