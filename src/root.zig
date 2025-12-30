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

/// Parse and render a Liquid template with the given context data.
pub fn render(allocator: std.mem.Allocator, template: []const u8, context: Value) ![]const u8 {
    var parser = Parser.init(allocator, template);

    var ast = try parser.parse();
    defer ast.deinit();

    // Don't deinit parser here - the AST owns the token references
    // which point into the parser's token array

    var renderer = Renderer.init(allocator, context);
    defer renderer.deinit();

    const result = try renderer.render(ast);

    // Now it's safe to deinit the parser since we've finished rendering
    parser.deinit();

    return result;
}

test {
    std.testing.refAllDecls(@This());
}
