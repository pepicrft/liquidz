//! Liquidz - A Liquid template parsing and rendering library for Zig
//!
//! This library provides a complete implementation of the Liquid template language,
//! including lexing, parsing, and rendering capabilities.
//!
//! Architecture:
//! - lexer.zig: Tokenizes template strings into a stream of tokens
//! - parser.zig: Converts tokens into an Abstract Syntax Tree (AST)
//! - renderer.zig: Evaluates the AST against a context to produce output
//! - value.zig: Type-safe value representation (nil, bool, int, float, string, array, object)
//! - filters.zig: Built-in Liquid filter implementations
//!
//! Extensibility:
//! - Custom filters can be registered via FilterRegistry
//! - Use renderWithFilters() to render with custom filters
//!
//! Memory: All memory is managed through explicit Zig Allocator patterns.
//! Performance: No regex, minimal allocations, lazy evaluation where possible.

const std = @import("std");

pub const Lexer = @import("lexer.zig").Lexer;
pub const Token = @import("lexer.zig").Token;
pub const Parser = @import("parser.zig").Parser;
pub const Node = @import("parser.zig").Node;
pub const Renderer = @import("renderer.zig").Renderer;
pub const Value = @import("value.zig").Value;
pub const Filters = @import("filters.zig");

// Re-export extensibility types
pub const FilterRegistry = @import("filters.zig").FilterRegistry;
pub const FilterFn = @import("filters.zig").FilterFn;
pub const FilterError = @import("filters.zig").FilterError;

/// Parse and render a Liquid template with the given context data.
pub fn render(allocator: std.mem.Allocator, template: []const u8, context: Value) ![]const u8 {
    return renderWithFilters(allocator, template, context, null);
}

/// Parse and render a Liquid template with custom filters.
///
/// Example:
/// ```zig
/// var registry = FilterRegistry.init(allocator);
/// defer registry.deinit();
///
/// try registry.register("shout", struct {
///     fn filter(alloc: Allocator, value: Value, args: []const Value) FilterError!Value {
///         const str = value.toString() orelse "";
///         const result = std.ascii.allocUpperString(alloc, str) catch return FilterError.OutOfMemory;
///         // Add exclamation marks
///         const final = std.fmt.allocPrint(alloc, "{s}!!!", .{result}) catch return FilterError.OutOfMemory;
///         return Value.initString(final);
///     }
/// }.filter);
///
/// const output = try renderWithFilters(allocator, "{{ name | shout }}", context, &registry);
/// ```
pub fn renderWithFilters(
    allocator: std.mem.Allocator,
    template: []const u8,
    context: Value,
    filter_registry: ?*const FilterRegistry,
) ![]const u8 {
    var parser = Parser.init(allocator, template);

    var ast = try parser.parse();
    defer ast.deinit();

    var renderer = Renderer.initWithFilters(allocator, context, filter_registry);
    defer renderer.deinit();

    const result = try renderer.render(ast);

    parser.deinit();

    return result;
}

test {
    std.testing.refAllDecls(@This());
}
