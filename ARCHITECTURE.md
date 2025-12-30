# Liquidz Architecture

Liquidz is a high-performance Liquid template engine written in Zig, designed to beat Ruby's implementation through careful memory management and performance optimization.

## Module Structure

### Core Modules

#### `lexer.zig` (839 lines)
**Responsibility**: Tokenization of Liquid templates

- **Modes**: text, output (`{{ }}`), tag (`{% %}`), raw (for `{% raw %}` blocks)
- **Key Features**:
  - State machine for switching between modes
  - Handles Ruby Liquid's lax parsing (malformed strings, mixed operators)
  - Whitespace trimming support (`{{-` and `-%}`)
  - Keyword recognition via static string map
  - Position tracking (line/column) for error reporting

- **Performance Notes**:
  - Single-pass tokenization
  - Lookahead only for 2-3 characters
  - No regex - all character-by-character parsing
  - StringHashMap for keyword lookup (O(1) amortized)

#### `parser.zig` (1000 lines)
**Responsibility**: AST generation from tokens

- **Features**:
  - Recursive descent parser
  - Operator precedence handling (comparison → logical)
  - Right-associative logical operators
  - Lax mode: skips invalid tokens gracefully
  - Nested block parsing (if/elsif/else, for/endfor, etc.)
  - Filter chain parsing

- **Memory Strategy**:
  - `liquid_buffers`: Handles {% liquid %} tag expansion
  - No copying of token values - uses slice references
  - Deferred cleanup until rendering completes

#### `renderer.zig` (2000+ lines)
**Responsibility**: AST evaluation and output generation

- **Key Components**:
  - `Renderer`: Main struct managing evaluation state
  - `ForloopInfo`: Loop context (index, length, first/last)
  - `TablerowInfo`: HTML table row context
  - Local variable scoping with backup/restore
  - Filter application pipeline

- **Features**:
  - Variable scope management (global + local)
  - Counter state (increment/decrement)
  - Cycle indices for cycle tag
  - Protected variable shadowing for includes
  - Scratch allocator for temporary values

- **Performance**:
  - Lazy evaluation of branches
  - Single output buffer (ArrayList)
  - Minimal allocations via scratch allocator

#### `value.zig` (500+ lines)
**Responsibility**: Type-safe value representation

- **Types**:
  - `nil`, `boolean`, `integer`, `float`, `string`
  - `array`, `object` (StringArrayHashMap for ordering)
  - `range`, `empty`, `blank` (special Liquid types)
  - `liquid_error`, `boolean_drop` (special cases)

- **Operations**:
  - Truthiness evaluation (nil/false only falsy)
  - Type coercion for comparisons
  - Property access (`.` operator)
  - Index access (`[n]` for arrays, strings)
  - JSON parsing for CLI usage

- **Memory Safety**:
  - Explicit `deinit()` for cleanup
  - Deep recursion for nested structures
  - Reference semantics for immutable parts

#### `filters.zig` (400 lines)
**Responsibility**: Built-in Liquid filters

- **Categories**:
  - String filters: upcase, downcase, capitalize, reverse, strip, split, join
  - Math filters: plus, minus, times, divided_by, modulo, ceil, floor, round, abs
  - Array filters: first, last, join, size, reverse, sort, uniq, compact
  - Comparison filters: default, where, map

- **Design**:
  - Router function (`apply`) dispatches by name
  - No dynamic dispatch - all handled at compile time
  - Filter arguments passed as Value array
  - Returns new Value (immutable semantics)

#### `main.zig` (69 lines)
**Responsibility**: CLI tool

- Features:
  - File or stdin template input
  - JSON context data
  - Output to stdout
  - Error handling and usage display

#### `ffi.zig` (TBD)
**Responsibility**: C ABI for FFI integration

- Exports C-compatible functions for Ruby/other language bindings

## Data Flow

```
Template String
    ↓
[Lexer] → Tokens
    ↓
[Parser] → AST (Node tree)
    ↓
[Renderer] → Output String
```

## Memory Management Strategy

### Allocator Hierarchy
1. **Main Allocator**: Passed in for long-lived structures
2. **Work Allocator**: Scratch arena for temporary values during rendering
3. **Auto-cleanup**: Deinit traversals clean up allocated memory

### Memory Lifetime
- **Lexer Tokens**: Owned by parser, freed during parser deinit
- **AST Nodes**: Owned by parser, freed on deinit
- **Output Buffer**: Owned by renderer, returned to caller
- **Values**: Allocated as needed, returned or freed based on ownership
- **Local Variables**: Stored in StringHashMap, freed on scope exit

## Performance Optimizations

### Zero-Copy Where Possible
- Token values are slices into source (no copies)
- String literals from templates don't need escaping until output
- Array/object values reference parsed JSON

### Lazy Evaluation
- Branches (if/else) only evaluate taken path
- Short-circuit logic (and/or)
- Filters applied in order without intermediate allocations

### Efficient Data Structures
- StringHashMap for variable/counter/cycle lookups (O(1))
- ArrayList for output buffering (amortized O(1) append)
- StringArrayHashMap preserves JSON key order

### Minimal Allocations
- Scratch arena for filter results
- Single pass over token stream
- No backtracking in parser

## Testing

### Test Suites
1. **Unit Tests**: Built into modules with `zig test`
2. **Golden Liquid**: Community test suite (1000+ tests)
3. **Liquid Spec**: Official Shopify test suite

### CI/CD
- GitHub Actions with Mise for tool management
- Separate jobs for units, golden, spec, WASM builds
- All tests run on every push

## Comparison to Ruby Liquid

| Aspect | Liquidz | Ruby Liquid |
|--------|---------|------------|
| Memory | Explicit allocation | GC-managed |
| Speed | Native code | Interpreted |
| Startup | Fast | Slower (GC) |
| Throughput | No GC pauses | GC pauses |
| Code size | 2.5K lines | 10K+ lines |
| Dependencies | None | gems required |

## Future Optimizations

1. **WASM Target**: Already supported (zig build wasm)
2. **FFI Integration**: C ABI library for calling from Ruby/Python/etc
3. **Template Caching**: AST caching layer
4. **Streaming Output**: Render to file instead of string
5. **Parallel Rendering**: If loops parallelization
