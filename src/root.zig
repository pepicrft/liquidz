//! Liquidz - A Liquid template parsing and rendering library for Zig
//!
//! This library provides a complete implementation of the Liquid template language,
//! including lexing, parsing, and rendering capabilities.

const std = @import("std");

pub const Lexer = @import("lexer.zig").Lexer;
pub const Token = @import("lexer.zig").Token;
pub const Parser = @import("parser.zig").Parser;
pub const Node = @import("parser.zig").Node;
pub const Renderer = @import("renderer.zig").Renderer;
pub const Value = @import("value.zig").Value;

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
