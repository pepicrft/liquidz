//! Lexer for Liquid templates.
//! Tokenizes the template into a stream of tokens for parsing.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TokenType = enum {
    // Literals
    text,
    string,
    integer,
    float,

    // Identifiers and keywords
    identifier,
    nil,
    true_lit,
    false_lit,
    blank,
    empty,
    liquid_content,
    inline_comment,

    // Delimiters
    output_start, // {{
    output_end, // }}
    tag_start, // {%
    tag_end, // %}
    output_start_trim, // {{-
    output_end_trim, // -}}
    tag_start_trim, // {%-
    tag_end_trim, // -%}

    // Operators
    pipe, // |
    dot, // .
    comma, // ,
    colon, // :
    lparen, // (
    rparen, // )
    lbracket, // [
    rbracket, // ]
    range, // ..
    eq, // ==
    ne, // !=
    lt, // <
    gt, // >
    le, // <=
    ge, // >=
    assign, // =

    // Keywords (tags)
    kw_if,
    kw_elsif,
    kw_else,
    kw_endif,
    kw_unless,
    kw_endunless,
    kw_case,
    kw_when,
    kw_endcase,
    kw_for,
    kw_endfor,
    kw_break,
    kw_continue,
    kw_in,
    kw_assign,
    kw_capture,
    kw_endcapture,
    kw_increment,
    kw_decrement,
    kw_cycle,
    kw_tablerow,
    kw_endtablerow,
    kw_include,
    kw_render,
    kw_raw,
    kw_endraw,
    kw_comment,
    kw_endcomment,
    kw_liquid,
    kw_echo,
    kw_and,
    kw_or,
    kw_not,
    kw_contains,
    kw_with,
    kw_as,
    kw_limit,
    kw_offset,
    kw_reversed,
    kw_cols,
    kw_ifchanged,
    kw_endifchanged,
    kw_doc,
    kw_enddoc,

    // Special
    eof,
    err,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    line: usize,
    column: usize,

    pub fn init(token_type: TokenType, value: []const u8, line: usize, column: usize) Token {
        return .{
            .type = token_type,
            .value = value,
            .line = line,
            .column = column,
        };
    }
};

pub const LexerMode = enum {
    text,
    output,
    tag,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    mode: LexerMode,
    tag_token_count: usize,
    liquid_mode: bool,
    allocator: Allocator,
    tokens: std.ArrayList(Token),

    const Self = @This();

    pub fn init(allocator: Allocator, source: []const u8) Self {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .mode = .text,
            .tag_token_count = 0,
            .liquid_mode = false,
            .allocator = allocator,
            .tokens = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn tokenize(self: *Self) ![]Token {
        while (self.pos < self.source.len) {
            switch (self.mode) {
                .text => try self.tokenizeText(),
                .output => try self.tokenizeOutput(),
                .tag => try self.tokenizeTag(),
            }
        }

        try self.tokens.append(self.allocator, Token.init(.eof, "", self.line, self.column));
        return self.tokens.toOwnedSlice(self.allocator);
    }

    fn tokenizeText(self: *Self) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.column;

        while (self.pos < self.source.len) {
            if (self.pos + 1 < self.source.len) {
                const c1 = self.source[self.pos];
                const c2 = self.source[self.pos + 1];

                if (c1 == '{' and (c2 == '{' or c2 == '%')) {
                    // Found start of output or tag
                    if (self.pos > start) {
                        try self.tokens.append(self.allocator, Token.init(.text, self.source[start..self.pos], start_line, start_col));
                    }

                    // Check for whitespace trim
                    if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '-') {
                        if (c2 == '{') {
                            try self.tokens.append(self.allocator, Token.init(.output_start_trim, "{{-", self.line, self.column));
                            self.advance();
                            self.advance();
                            self.advance();
                            self.mode = .output;
                        } else {
                            try self.tokens.append(self.allocator, Token.init(.tag_start_trim, "{%-", self.line, self.column));
                            self.advance();
                            self.advance();
                            self.advance();
                            self.mode = .tag;
                            self.tag_token_count = 0;
                            self.liquid_mode = false;
                        }
                    } else {
                        if (c2 == '{') {
                            try self.tokens.append(self.allocator, Token.init(.output_start, "{{", self.line, self.column));
                            self.advance();
                            self.advance();
                            self.mode = .output;
                        } else {
                            try self.tokens.append(self.allocator, Token.init(.tag_start, "{%", self.line, self.column));
                            self.advance();
                            self.advance();
                            self.mode = .tag;
                            self.tag_token_count = 0;
                            self.liquid_mode = false;
                        }
                    }
                    return;
                }
            }

            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }

        // Remaining text
        if (self.pos > start) {
            try self.tokens.append(self.allocator, Token.init(.text, self.source[start..self.pos], start_line, start_col));
        }
    }

    fn tokenizeOutput(self: *Self) !void {
        try self.skipWhitespace();

        if (self.pos >= self.source.len) {
            try self.tokens.append(self.allocator, Token.init(.err, "Unexpected end of input in output", self.line, self.column));
            return;
        }

        // Check for end of output
        if (self.peek() == '-' and self.pos + 2 < self.source.len and
            self.source[self.pos + 1] == '}' and self.source[self.pos + 2] == '}')
        {
            try self.tokens.append(self.allocator, Token.init(.output_end_trim, "-}}", self.line, self.column));
            self.advance();
            self.advance();
            self.advance();
            self.mode = .text;
            return;
        }

        if (self.peek() == '}' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '}') {
            try self.tokens.append(self.allocator, Token.init(.output_end, "}}", self.line, self.column));
            self.advance();
            self.advance();
            self.mode = .text;
            return;
        }

        _ = try self.tokenizeExpression();
    }

    fn tokenizeTag(self: *Self) !void {
        if (self.liquid_mode) {
            if (self.peek() == '-' and self.pos + 2 < self.source.len and
                self.source[self.pos + 1] == '%' and self.source[self.pos + 2] == '}')
            {
                try self.tokens.append(self.allocator, Token.init(.tag_end_trim, "-%}", self.line, self.column));
                self.advance();
                self.advance();
                self.advance();
                self.mode = .text;
                self.liquid_mode = false;
                return;
            }

            if (self.peek() == '%' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '}') {
                try self.tokens.append(self.allocator, Token.init(.tag_end, "%}", self.line, self.column));
                self.advance();
                self.advance();
                self.mode = .text;
                self.liquid_mode = false;
                return;
            }

            try self.tokenizeLiquidContent();
            return;
        }

        try self.skipWhitespace();

        if (self.pos >= self.source.len) {
            try self.tokens.append(self.allocator, Token.init(.err, "Unexpected end of input in tag", self.line, self.column));
            return;
        }

        if (self.peek() == '#') {
            try self.tokenizeInlineComment();
            return;
        }

        // Check for end of tag
        if (self.peek() == '-' and self.pos + 2 < self.source.len and
            self.source[self.pos + 1] == '%' and self.source[self.pos + 2] == '}')
        {
            try self.tokens.append(self.allocator, Token.init(.tag_end_trim, "-%}", self.line, self.column));
            self.advance();
            self.advance();
            self.advance();
            self.mode = .text;
            return;
        }

        if (self.peek() == '%' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '}') {
            try self.tokens.append(self.allocator, Token.init(.tag_end, "%}", self.line, self.column));
            self.advance();
            self.advance();
            self.mode = .text;
            return;
        }

        const token_type = try self.tokenizeExpression();
        if (self.tag_token_count == 0 and token_type == .kw_liquid) {
            self.liquid_mode = true;
        }
        self.tag_token_count += 1;
    }

    fn emitToken(self: *Self, token_type: TokenType, value: []const u8, advance_count: u8) !TokenType {
        try self.tokens.append(self.allocator, Token.init(token_type, value, self.line, self.column));
        var i: u8 = 0;
        while (i < advance_count) : (i += 1) self.advance();
        return token_type;
    }

    fn peekNext(self: *Self) u8 {
        return if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;
    }

    fn tokenizeExpression(self: *Self) !TokenType {
        const c = self.peek();

        // String literals
        if (c == '"' or c == '\'') {
            try self.tokenizeString();
            return .string;
        }

        // Numbers
        if (std.ascii.isDigit(c) or (c == '-' and std.ascii.isDigit(self.peekNext()))) {
            try self.tokenizeNumber();
            return if (self.tokens.items.len > 0) self.tokens.items[self.tokens.items.len - 1].type else .err;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            try self.tokenizeIdentifier();
            return if (self.tokens.items.len > 0) self.tokens.items[self.tokens.items.len - 1].type else .err;
        }

        // Single-char operators
        return switch (c) {
            '|' => self.emitToken(.pipe, "|", 1),
            ',' => self.emitToken(.comma, ",", 1),
            ':' => self.emitToken(.colon, ":", 1),
            '(' => self.emitToken(.lparen, "(", 1),
            ')' => self.emitToken(.rparen, ")", 1),
            '[' => self.emitToken(.lbracket, "[", 1),
            ']' => self.emitToken(.rbracket, "]", 1),
            '.' => if (self.peekNext() == '.') self.emitToken(.range, "..", 2) else self.emitToken(.dot, ".", 1),
            '=' => if (self.peekNext() == '=') self.emitToken(.eq, "==", 2) else self.emitToken(.assign, "=", 1),
            '!' => if (self.peekNext() == '=') self.emitToken(.ne, "!=", 2) else self.emitToken(.err, "Unexpected character: !", 1),
            '<' => if (self.peekNext() == '=') self.emitToken(.le, "<=", 2) else if (self.peekNext() == '>') self.emitToken(.ne, "<>", 2) else self.emitToken(.lt, "<", 1),
            '>' => if (self.peekNext() == '=') self.emitToken(.ge, ">=", 2) else self.emitToken(.gt, ">", 1),
            else => self.emitToken(.err, self.source[self.pos .. self.pos + 1], 1),
        };
    }

    fn tokenizeLiquidContent(self: *Self) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.column;

        while (self.pos < self.source.len) {
            if (self.peek() == '-' and self.pos + 2 < self.source.len and
                self.source[self.pos + 1] == '%' and self.source[self.pos + 2] == '}')
            {
                break;
            }
            if (self.peek() == '%' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '}') {
                break;
            }
            self.advance();
        }

        if (self.pos > start) {
            try self.tokens.append(self.allocator, Token.init(.liquid_content, self.source[start..self.pos], start_line, start_col));
        }
    }

    fn tokenizeInlineComment(self: *Self) !void {
        const start_line = self.line;
        const start_col = self.column;
        self.advance(); // consume '#'

        try self.tokens.append(self.allocator, Token.init(.inline_comment, "", start_line, start_col));

        while (self.pos < self.source.len) {
            if (self.peek() == '-' and self.pos + 2 < self.source.len and
                self.source[self.pos + 1] == '%' and self.source[self.pos + 2] == '}')
            {
                try self.tokens.append(self.allocator, Token.init(.tag_end_trim, "-%}", self.line, self.column));
                self.advance();
                self.advance();
                self.advance();
                self.mode = .text;
                return;
            }
            if (self.peek() == '%' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '}') {
                try self.tokens.append(self.allocator, Token.init(.tag_end, "%}", self.line, self.column));
                self.advance();
                self.advance();
                self.mode = .text;
                return;
            }
            self.advance();
        }

        try self.tokens.append(self.allocator, Token.init(.err, "Unexpected end of input in tag", self.line, self.column));
    }

    fn tokenizeString(self: *Self) !void {
        const quote = self.peek();
        const start_line = self.line;
        const start_col = self.column;
        self.advance(); // consume opening quote

        const start = self.pos;
        while (self.pos < self.source.len and self.peek() != quote) {
            if (self.peek() == '\\' and self.pos + 1 < self.source.len) {
                self.advance(); // skip escape char
            }
            self.advance();
        }

        const value = self.source[start..self.pos];

        if (self.pos < self.source.len) {
            self.advance(); // consume closing quote
        }

        try self.tokens.append(self.allocator, Token.init(.string, value, start_line, start_col));
    }

    fn tokenizeNumber(self: *Self) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.column;
        var is_float = false;

        if (self.peek() == '-') {
            self.advance();
        }

        while (self.pos < self.source.len and std.ascii.isDigit(self.peek())) {
            self.advance();
        }

        if (self.pos < self.source.len and self.peek() == '.' and
            self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1]))
        {
            is_float = true;
            self.advance(); // consume dot
            while (self.pos < self.source.len and std.ascii.isDigit(self.peek())) {
                self.advance();
            }
        }

        const value = self.source[start..self.pos];
        const token_type: TokenType = if (is_float) .float else .integer;
        try self.tokens.append(self.allocator, Token.init(token_type, value, start_line, start_col));
    }

    fn tokenizeIdentifier(self: *Self) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.column;

        while (self.pos < self.source.len) {
            const c = self.peek();
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') {
                self.advance();
            } else {
                break;
            }
        }

        const value = self.source[start..self.pos];
        const token_type = self.getKeywordType(value);
        try self.tokens.append(self.allocator, Token.init(token_type, value, start_line, start_col));
    }

    const keywords = std.StaticStringMap(TokenType).initComptime(.{
        .{ "if", .kw_if },
        .{ "elsif", .kw_elsif },
        .{ "else", .kw_else },
        .{ "endif", .kw_endif },
        .{ "unless", .kw_unless },
        .{ "endunless", .kw_endunless },
        .{ "case", .kw_case },
        .{ "when", .kw_when },
        .{ "endcase", .kw_endcase },
        .{ "for", .kw_for },
        .{ "endfor", .kw_endfor },
        .{ "break", .kw_break },
        .{ "continue", .kw_continue },
        .{ "in", .kw_in },
        .{ "assign", .kw_assign },
        .{ "capture", .kw_capture },
        .{ "endcapture", .kw_endcapture },
        .{ "increment", .kw_increment },
        .{ "decrement", .kw_decrement },
        .{ "cycle", .kw_cycle },
        .{ "tablerow", .kw_tablerow },
        .{ "endtablerow", .kw_endtablerow },
        .{ "include", .kw_include },
        .{ "render", .kw_render },
        .{ "raw", .kw_raw },
        .{ "endraw", .kw_endraw },
        .{ "comment", .kw_comment },
        .{ "endcomment", .kw_endcomment },
        .{ "liquid", .kw_liquid },
        .{ "echo", .kw_echo },
        .{ "and", .kw_and },
        .{ "or", .kw_or },
        .{ "not", .kw_not },
        .{ "contains", .kw_contains },
        .{ "with", .kw_with },
        .{ "as", .kw_as },
        .{ "limit", .kw_limit },
        .{ "offset", .kw_offset },
        .{ "reversed", .kw_reversed },
        .{ "cols", .kw_cols },
        .{ "nil", .nil },
        .{ "null", .nil },
        .{ "true", .true_lit },
        .{ "false", .false_lit },
        .{ "blank", .blank },
        .{ "empty", .empty },
        .{ "ifchanged", .kw_ifchanged },
        .{ "endifchanged", .kw_endifchanged },
        .{ "doc", .kw_doc },
        .{ "enddoc", .kw_enddoc },
    });

    fn getKeywordType(_: *Self, value: []const u8) TokenType {
        return keywords.get(value) orelse .identifier;
    }

    fn skipWhitespace(self: *Self) !void {
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.peek())) {
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }

    fn peek(self: *Self) u8 {
        if (self.pos >= self.source.len) return 0;
        return self.source[self.pos];
    }

    fn advance(self: *Self) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }
};

test "lexer basic output" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "{{ 'hello' }}");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expectEqual(TokenType.output_start, tokens[0].type);
    try std.testing.expectEqual(TokenType.string, tokens[1].type);
    try std.testing.expectEqualStrings("hello", tokens[1].value);
    try std.testing.expectEqual(TokenType.output_end, tokens[2].type);
}

test "lexer text and output" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "Hello {{ name }}!");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expectEqual(TokenType.text, tokens[0].type);
    try std.testing.expectEqualStrings("Hello ", tokens[0].value);
    try std.testing.expectEqual(TokenType.output_start, tokens[1].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[2].type);
    try std.testing.expectEqualStrings("name", tokens[2].value);
    try std.testing.expectEqual(TokenType.output_end, tokens[3].type);
    try std.testing.expectEqual(TokenType.text, tokens[4].type);
    try std.testing.expectEqualStrings("!", tokens[4].value);
}

test "lexer tag" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "{% assign x = 5 %}");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expectEqual(TokenType.tag_start, tokens[0].type);
    try std.testing.expectEqual(TokenType.kw_assign, tokens[1].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[2].type);
    try std.testing.expectEqual(TokenType.assign, tokens[3].type);
    try std.testing.expectEqual(TokenType.integer, tokens[4].type);
    try std.testing.expectEqual(TokenType.tag_end, tokens[5].type);
}
