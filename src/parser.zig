//! Parser for Liquid templates.
//! Converts a stream of tokens into an Abstract Syntax Tree (AST).

const std = @import("std");
const Allocator = std.mem.Allocator;
const lexer_mod = @import("lexer.zig");
const Token = lexer_mod.Token;
const TokenType = lexer_mod.TokenType;
const Lexer = lexer_mod.Lexer;

pub const NodeType = enum {
    root,
    text,
    output,
    variable,
    literal_string,
    literal_integer,
    literal_float,
    literal_bool,
    literal_nil,
    range,
    filter,
    property_access,
    index_access,
    if_tag,
    unless_tag,
    elsif_branch,
    else_branch,
    for_tag,
    assign_tag,
    capture_tag,
    case_tag,
    when_branch,
    cycle_tag,
    increment_tag,
    decrement_tag,
    tablerow_tag,
    include_tag,
    render_tag,
    raw_tag,
    comment_tag,
    liquid_tag,
    echo_tag,
    break_tag,
    continue_tag,
    ifchanged_tag,
    doc_tag,
    expression,
    comparison,
    logical,
};

pub const Node = struct {
    type: NodeType,
    value: ?[]const u8 = null,
    children: std.ArrayList(Node),
    allocator: Allocator,

    // Additional fields for specific node types
    filter_name: ?[]const u8 = null,
    filter_args: ?std.ArrayList(Node) = null,
    operator: ?[]const u8 = null,
    trim_left: bool = false,
    trim_right: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator, node_type: NodeType) Self {
        return .{
            .type = node_type,
            .children = .empty,
            .allocator = allocator,
        };
    }

    pub fn initWithValue(allocator: Allocator, node_type: NodeType, value: []const u8) Self {
        var node = init(allocator, node_type);
        node.value = value;
        return node;
    }

    pub fn deinit(self: *Self) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit(self.allocator);
        if (self.filter_args) |*args| {
            for (args.items) |*arg| {
                arg.deinit();
            }
            args.deinit(self.allocator);
        }
    }

    pub fn addChild(self: *Self, child: Node) !void {
        try self.children.append(self.allocator, child);
    }
};

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEndOfInput,
    InvalidSyntax,
    OutOfMemory,
};

pub const Parser = struct {
    allocator: Allocator,
    tokens: []Token,
    pos: usize,
    source: []const u8,
    lexer: ?Lexer,
    liquid_buffers: std.ArrayList([]u8),

    const Self = @This();

    pub fn init(allocator: Allocator, source: []const u8) Self {
        return .{
            .allocator = allocator,
            .tokens = &[_]Token{},
            .pos = 0,
            .source = source,
            .lexer = null,
            .liquid_buffers = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.lexer) |*lex| {
            lex.deinit();
        }
        if (self.tokens.len > 0) {
            self.allocator.free(self.tokens);
        }
        for (self.liquid_buffers.items) |buf| {
            self.allocator.free(buf);
        }
        self.liquid_buffers.deinit(self.allocator);
    }

    pub fn parse(self: *Self) ParseError!Node {
        var lex = Lexer.init(self.allocator, self.source);
        self.tokens = lex.tokenize() catch return ParseError.OutOfMemory;
        self.lexer = lex;

        var root = Node.init(self.allocator, .root);

        while (!self.isAtEnd()) {
            const node = try self.parseNode();
            root.addChild(node) catch return ParseError.OutOfMemory;
        }

        return root;
    }

    fn parseNode(self: *Self) ParseError!Node {
        const token = self.peek();

        return switch (token.type) {
            .text => self.parseText(),
            .output_start, .output_start_trim => self.parseOutput(),
            .tag_start, .tag_start_trim => self.parseTag(),
            .eof => ParseError.UnexpectedEndOfInput,
            else => ParseError.UnexpectedToken,
        };
    }

    fn parseText(self: *Self) ParseError!Node {
        const token = self.advance();
        return Node.initWithValue(self.allocator, .text, token.value);
    }

    fn parseOutput(self: *Self) ParseError!Node {
        const start_token = self.advance();
        const trim_left = start_token.type == .output_start_trim;

        var node = Node.init(self.allocator, .output);
        node.trim_left = trim_left;

        // Parse the expression
        const expr = try self.parseExpression();
        node.addChild(expr) catch return ParseError.OutOfMemory;

        // Parse filters
        while (self.check(.pipe)) {
            _ = self.advance(); // consume pipe
            const filter = try self.parseFilter();
            node.addChild(filter) catch return ParseError.OutOfMemory;
        }

        // Expect end of output
        if (self.check(.output_end_trim)) {
            node.trim_right = true;
            _ = self.advance();
        } else if (self.check(.output_end)) {
            _ = self.advance();
        } else {
            return ParseError.InvalidSyntax;
        }

        return node;
    }

    fn parseExpression(self: *Self) ParseError!Node {
        return self.parseLogicalOr();
    }

    fn parseLogicalOr(self: *Self) ParseError!Node {
        var left = try self.parseLogicalAnd();

        while (self.check(.kw_or)) {
            const op = self.advance();
            const right = try self.parseLogicalAnd();

            var node = Node.init(self.allocator, .logical);
            node.operator = op.value;
            try node.addChild(left);
            try node.addChild(right);
            left = node;
        }

        return left;
    }

    fn parseLogicalAnd(self: *Self) ParseError!Node {
        var left = try self.parseComparison();

        while (self.check(.kw_and)) {
            const op = self.advance();
            const right = try self.parseComparison();

            var node = Node.init(self.allocator, .logical);
            node.operator = op.value;
            try node.addChild(left);
            try node.addChild(right);
            left = node;
        }

        return left;
    }

    fn parseComparison(self: *Self) ParseError!Node {
        const left = try self.parsePrimary();

        const is_comparison = switch (self.peek().type) {
            .eq, .ne, .lt, .gt, .le, .ge, .kw_contains => true,
            else => false,
        };

        if (!is_comparison) return left;

        const op = self.advance();
        const right = try self.parsePrimary();

        var node = Node.init(self.allocator, .comparison);
        node.operator = op.value;
        try node.addChild(left);
        try node.addChild(right);
        return node;
    }

    fn parsePrimary(self: *Self) ParseError!Node {
        const token = self.peek();

        switch (token.type) {
            .string => {
                _ = self.advance();
                return Node.initWithValue(self.allocator, .literal_string, token.value);
            },
            .integer => {
                _ = self.advance();
                return Node.initWithValue(self.allocator, .literal_integer, token.value);
            },
            .float => {
                _ = self.advance();
                return Node.initWithValue(self.allocator, .literal_float, token.value);
            },
            .true_lit => {
                _ = self.advance();
                return Node.initWithValue(self.allocator, .literal_bool, "true");
            },
            .false_lit => {
                _ = self.advance();
                return Node.initWithValue(self.allocator, .literal_bool, "false");
            },
            .nil => {
                _ = self.advance();
                return Node.init(self.allocator, .literal_nil);
            },
            .blank, .empty => {
                _ = self.advance();
                return Node.initWithValue(self.allocator, .literal_string, "");
            },
            .identifier => {
                return self.parseVariable();
            },
            .lparen => {
                // Could be a range or grouped expression
                _ = self.advance(); // consume (
                const start = try self.parsePrimary();

                if (self.check(.range)) {
                    _ = self.advance(); // consume ..
                    const end = try self.parsePrimary();

                    if (!self.check(.rparen)) {
                        return ParseError.InvalidSyntax;
                    }
                    _ = self.advance(); // consume )

                    var range_node = Node.init(self.allocator, .range);
                    range_node.addChild(start) catch return ParseError.OutOfMemory;
                    range_node.addChild(end) catch return ParseError.OutOfMemory;
                    return range_node;
                }

                if (!self.check(.rparen)) {
                    return ParseError.InvalidSyntax;
                }
                _ = self.advance(); // consume )
                return start;
            },
            .lbracket => {
                // Bracketed variable access at start
                return self.parseVariable();
            },
            else => return ParseError.UnexpectedToken,
        }
    }

    fn parseVariable(self: *Self) ParseError!Node {
        var node: Node = undefined;

        // Handle bracketed start
        if (self.check(.lbracket)) {
            _ = self.advance(); // consume [

            if (self.check(.string)) {
                const str_token = self.advance();
                node = Node.initWithValue(self.allocator, .variable, str_token.value);
            } else {
                const inner = try self.parseExpression();
                node = Node.init(self.allocator, .index_access);
                // Create a placeholder variable node
                const base = Node.initWithValue(self.allocator, .variable, "");
                node.addChild(base) catch return ParseError.OutOfMemory;
                node.addChild(inner) catch return ParseError.OutOfMemory;
            }

            if (!self.check(.rbracket)) {
                return ParseError.InvalidSyntax;
            }
            _ = self.advance(); // consume ]
        } else {
            const token = self.advance();
            node = Node.initWithValue(self.allocator, .variable, token.value);
        }

        // Parse property/index accesses
        while (true) {
            if (self.check(.dot)) {
                _ = self.advance(); // consume .
                if (!self.check(.identifier)) {
                    return ParseError.InvalidSyntax;
                }
                const prop_token = self.advance();

                var prop_node = Node.init(self.allocator, .property_access);
                prop_node.value = prop_token.value;
                prop_node.addChild(node) catch return ParseError.OutOfMemory;
                node = prop_node;
            } else if (self.check(.lbracket)) {
                _ = self.advance(); // consume [

                var index_node = Node.init(self.allocator, .index_access);
                index_node.addChild(node) catch return ParseError.OutOfMemory;

                if (self.check(.string)) {
                    const str_token = self.advance();
                    const str_node = Node.initWithValue(self.allocator, .literal_string, str_token.value);
                    index_node.addChild(str_node) catch return ParseError.OutOfMemory;
                } else {
                    const index_expr = try self.parseExpression();
                    index_node.addChild(index_expr) catch return ParseError.OutOfMemory;
                }

                if (!self.check(.rbracket)) {
                    return ParseError.InvalidSyntax;
                }
                _ = self.advance(); // consume ]
                node = index_node;
            } else {
                break;
            }
        }

        return node;
    }

    fn parseFilter(self: *Self) ParseError!Node {
        if (!self.check(.identifier)) {
            return ParseError.InvalidSyntax;
        }

        const filter_name = self.advance();
        var node = Node.init(self.allocator, .filter);
        node.filter_name = filter_name.value;
        node.filter_args = .empty;

        // Parse filter arguments
        if (self.check(.colon)) {
            _ = self.advance(); // consume :

            // Parse first argument
            const arg = try self.parseFilterArg();
            node.filter_args.?.append(self.allocator, arg) catch return ParseError.OutOfMemory;

            // Parse additional arguments
            while (self.check(.comma)) {
                _ = self.advance(); // consume ,
                const next_arg = try self.parseFilterArg();
                node.filter_args.?.append(self.allocator, next_arg) catch return ParseError.OutOfMemory;
            }
        }

        return node;
    }

    fn parseFilterArg(self: *Self) ParseError!Node {
        // Check for named argument (e.g., allow_false: true)
        if (self.check(.identifier)) {
            const maybe_name = self.peek();
            // Look ahead for colon
            if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].type == .colon) {
                _ = self.advance(); // consume identifier
                _ = self.advance(); // consume colon
                var named_arg = Node.init(self.allocator, .expression);
                named_arg.value = maybe_name.value;
                const arg_value = try self.parsePrimary();
                named_arg.addChild(arg_value) catch return ParseError.OutOfMemory;
                return named_arg;
            }
        }

        return self.parsePrimary();
    }

    fn parseTag(self: *Self) ParseError!Node {
        const start_token = self.advance();
        const trim_left = start_token.type == .tag_start_trim;

        const tag_token = self.peek();

        var node = switch (tag_token.type) {
            .kw_if => try self.parseIfTag(),
            .kw_unless => try self.parseUnlessTag(),
            .kw_for => try self.parseForTag(),
            .kw_assign => try self.parseAssignTag(),
            .kw_capture => try self.parseCaptureTag(),
            .kw_case => try self.parseCaseTag(),
            .kw_cycle => try self.parseCycleTag(),
            .kw_increment => try self.parseIncrementTag(),
            .kw_decrement => try self.parseDecrementTag(),
            .kw_tablerow => try self.parseTablerowTag(),
            .kw_include => try self.parseIncludeTag(),
            .kw_render => try self.parseRenderTag(),
            .kw_raw => try self.parseRawTag(),
            .kw_comment => try self.parseCommentTag(),
            .kw_liquid => try self.parseLiquidTag(),
            .kw_echo => try self.parseEchoTag(),
            .kw_break => try self.parseBreakTag(),
            .kw_continue => try self.parseContinueTag(),
            .kw_ifchanged => try self.parseIfchangedTag(),
            .kw_doc => try self.parseDocTag(),
            .inline_comment => try self.parseInlineCommentTag(),
            else => return ParseError.UnexpectedToken,
        };

        node.trim_left = trim_left;
        return node;
    }

    fn parseIfTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'if'

        var node = Node.init(self.allocator, .if_tag);

        // Parse condition
        const condition = try self.parseExpression();
        node.addChild(condition) catch return ParseError.OutOfMemory;

        try self.expectTagEnd(&node);

        // Parse body and branches
        try self.parseIfBody(&node);

        return node;
    }

    fn parseIfBody(self: *Self, node: *Node) ParseError!void {
        // Parse body nodes until elsif, else, or endif
        while (!self.isAtEnd()) {
            const token = self.peek();

            if (token.type == .text) {
                const text_node = try self.parseText();
                node.addChild(text_node) catch return ParseError.OutOfMemory;
            } else if (token.type == .output_start or token.type == .output_start_trim) {
                const output_node = try self.parseOutput();
                node.addChild(output_node) catch return ParseError.OutOfMemory;
            } else if (token.type == .tag_start or token.type == .tag_start_trim) {
                _ = self.advance(); // consume {%

                const tag_token = self.peek();

                if (tag_token.type == .kw_elsif) {
                    _ = self.advance(); // consume 'elsif'
                    var elsif_node = Node.init(self.allocator, .elsif_branch);
                    const elsif_cond = try self.parseExpression();
                    elsif_node.addChild(elsif_cond) catch return ParseError.OutOfMemory;
                    try self.expectTagEnd(&elsif_node);
                    try self.parseIfBody(&elsif_node);
                    node.addChild(elsif_node) catch return ParseError.OutOfMemory;
                    return;
                } else if (tag_token.type == .kw_else) {
                    _ = self.advance(); // consume 'else'
                    var else_node = Node.init(self.allocator, .else_branch);
                    try self.expectTagEnd(&else_node);
                    try self.parseIfBody(&else_node);
                    node.addChild(else_node) catch return ParseError.OutOfMemory;
                    return;
                } else if (tag_token.type == .kw_endif) {
                    _ = self.advance(); // consume 'endif'
                    try self.expectTagEnd(node);
                    return;
                } else {
                    // It's a nested tag
                    self.pos -= 1; // back up to tag_start
                    const nested = try self.parseTag();
                    node.addChild(nested) catch return ParseError.OutOfMemory;
                }
            } else {
                break;
            }
        }
    }

    fn parseUnlessTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'unless'

        var node = Node.init(self.allocator, .unless_tag);

        // Parse condition
        const condition = try self.parseExpression();
        node.addChild(condition) catch return ParseError.OutOfMemory;

        try self.expectTagEnd(&node);

        // Parse body
        try self.parseUnlessBody(&node);

        return node;
    }

    const BodyParser = *const fn (*Self, *Node) ParseError!void;

    fn parseBodyUntil(
        self: *Self,
        node: *Node,
        end_keyword: TokenType,
        else_keyword: ?TokenType,
        else_body_parser: ?BodyParser,
    ) ParseError!void {
        while (!self.isAtEnd()) {
            const token = self.peek();

            if (token.type == .text) {
                node.addChild(try self.parseText()) catch return ParseError.OutOfMemory;
            } else if (token.type == .output_start or token.type == .output_start_trim) {
                node.addChild(try self.parseOutput()) catch return ParseError.OutOfMemory;
            } else if (token.type == .tag_start or token.type == .tag_start_trim) {
                _ = self.advance();
                const tag_token = self.peek();

                if (else_keyword != null and tag_token.type == else_keyword.?) {
                    _ = self.advance();
                    var else_node = Node.init(self.allocator, .else_branch);
                    try self.expectTagEnd(&else_node);
                    if (else_body_parser) |parser| {
                        try parser(self, &else_node);
                    }
                    node.addChild(else_node) catch return ParseError.OutOfMemory;
                    return;
                } else if (tag_token.type == end_keyword) {
                    _ = self.advance();
                    try self.expectTagEnd(node);
                    return;
                } else {
                    self.pos -= 1;
                    node.addChild(try self.parseTag()) catch return ParseError.OutOfMemory;
                }
            } else {
                break;
            }
        }
    }

    fn parseUnlessBody(self: *Self, node: *Node) ParseError!void {
        try self.parseBodyUntil(node, .kw_endunless, .kw_else, parseUnlessBody);
    }

    fn parseForTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'for'

        var node = Node.init(self.allocator, .for_tag);

        // Parse loop variable
        if (!self.check(.identifier)) {
            return ParseError.InvalidSyntax;
        }
        const loop_var = self.advance();
        node.value = loop_var.value;

        // Expect 'in'
        if (!self.check(.kw_in)) {
            return ParseError.InvalidSyntax;
        }
        _ = self.advance();

        // Parse iterable expression
        const iterable = try self.parseExpression();
        node.addChild(iterable) catch return ParseError.OutOfMemory;

        // Parse optional parameters (limit, offset, reversed)
        while (self.check(.kw_limit) or self.check(.kw_offset) or self.check(.kw_reversed)) {
            const param = self.advance();
            var param_node = Node.initWithValue(self.allocator, .expression, param.value);

            if (param.type != .kw_reversed) {
                if (!self.check(.colon)) {
                    return ParseError.InvalidSyntax;
                }
                _ = self.advance();
                if (param.type == .kw_offset and self.check(.kw_continue)) {
                    _ = self.advance();
                    const value = Node.initWithValue(self.allocator, .literal_string, "continue");
                    param_node.addChild(value) catch return ParseError.OutOfMemory;
                } else {
                    const value = try self.parsePrimary();
                    param_node.addChild(value) catch return ParseError.OutOfMemory;
                }
            }

            node.addChild(param_node) catch return ParseError.OutOfMemory;
        }

        try self.expectTagEnd(&node);

        // Parse body
        try self.parseForBody(&node);

        return node;
    }

    fn parseForBody(self: *Self, node: *Node) ParseError!void {
        try self.parseBodyUntil(node, .kw_endfor, .kw_else, parseForBody);
    }

    fn parseAssignTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'assign'

        var node = Node.init(self.allocator, .assign_tag);

        // Parse variable name
        if (!self.check(.identifier)) {
            return ParseError.InvalidSyntax;
        }
        const var_name = self.advance();
        node.value = var_name.value;

        // Expect '='
        if (!self.check(.assign)) {
            return ParseError.InvalidSyntax;
        }
        _ = self.advance();

        // Parse value expression
        const value = try self.parseExpression();
        node.addChild(value) catch return ParseError.OutOfMemory;

        // Parse filters
        while (self.check(.pipe)) {
            _ = self.advance();
            const filter = try self.parseFilter();
            node.addChild(filter) catch return ParseError.OutOfMemory;
        }

        try self.expectTagEnd(&node);

        return node;
    }

    fn parseCaptureTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'capture'

        var node = Node.init(self.allocator, .capture_tag);

        // Parse variable name
        if (!self.check(.identifier)) {
            return ParseError.InvalidSyntax;
        }
        const var_name = self.advance();
        node.value = var_name.value;

        try self.expectTagEnd(&node);

        // Parse body until endcapture
        try self.parseCaptureBody(&node);

        return node;
    }

    fn parseCaptureBody(self: *Self, node: *Node) ParseError!void {
        try self.parseBodyUntil(node, .kw_endcapture, null, null);
    }

    fn parseCaseTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'case'

        var node = Node.init(self.allocator, .case_tag);

        // Parse expression to match
        const expr = try self.parseExpression();
        node.addChild(expr) catch return ParseError.OutOfMemory;

        try self.expectTagEnd(&node);

        // Parse when/else branches until endcase
        try self.parseCaseBody(&node);

        return node;
    }

    fn parseCaseBody(self: *Self, node: *Node) ParseError!void {
        while (!self.isAtEnd()) {
            const token = self.peek();

            if (token.type == .text) {
                // Skip whitespace-only text between when branches
                _ = self.advance();
            } else if (token.type == .tag_start or token.type == .tag_start_trim) {
                _ = self.advance();

                const tag_token = self.peek();

                if (tag_token.type == .kw_when) {
                    _ = self.advance();
                    var when_node = Node.init(self.allocator, .when_branch);

                    // Parse when values (can be comma-separated)
                    const when_val = try self.parsePrimary();
                    when_node.addChild(when_val) catch return ParseError.OutOfMemory;

                    while (self.check(.comma) or self.check(.kw_or)) {
                        _ = self.advance();
                        const next_val = try self.parsePrimary();
                        when_node.addChild(next_val) catch return ParseError.OutOfMemory;
                    }

                    try self.expectTagEnd(&when_node);
                    try self.parseWhenBody(&when_node);
                    node.addChild(when_node) catch return ParseError.OutOfMemory;
                } else if (tag_token.type == .kw_else) {
                    _ = self.advance();
                    var else_node = Node.init(self.allocator, .else_branch);
                    try self.expectTagEnd(&else_node);
                    try self.parseWhenBody(&else_node);
                    node.addChild(else_node) catch return ParseError.OutOfMemory;
                } else if (tag_token.type == .kw_endcase) {
                    _ = self.advance();
                    try self.expectTagEnd(node);
                    return;
                } else {
                    return ParseError.InvalidSyntax;
                }
            } else {
                break;
            }
        }
    }

    fn parseWhenBody(self: *Self, node: *Node) ParseError!void {
        while (!self.isAtEnd()) {
            const token = self.peek();

            if (token.type == .text) {
                const text_node = try self.parseText();
                node.addChild(text_node) catch return ParseError.OutOfMemory;
            } else if (token.type == .output_start or token.type == .output_start_trim) {
                const output_node = try self.parseOutput();
                node.addChild(output_node) catch return ParseError.OutOfMemory;
            } else if (token.type == .tag_start or token.type == .tag_start_trim) {
                // Check what's next without consuming
                if (self.pos + 1 < self.tokens.len) {
                    const next = self.tokens[self.pos + 1];
                    if (next.type == .kw_when or next.type == .kw_else or next.type == .kw_endcase) {
                        return; // End of this when body
                    }
                }
                const nested = try self.parseTag();
                node.addChild(nested) catch return ParseError.OutOfMemory;
            } else {
                break;
            }
        }
    }

    fn parseCycleTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'cycle'

        var node = Node.init(self.allocator, .cycle_tag);

        // Check for optional group name
        if (self.check(.string)) {
            const group = self.advance();
            if (self.check(.colon)) {
                node.value = group.value;
                _ = self.advance(); // consume :
            } else {
                // It's a cycle value, not a group
                const val_node = Node.initWithValue(self.allocator, .literal_string, group.value);
                node.addChild(val_node) catch return ParseError.OutOfMemory;
            }
        }

        // Parse cycle values
        while (!self.check(.tag_end) and !self.check(.tag_end_trim)) {
            const val = try self.parsePrimary();
            node.addChild(val) catch return ParseError.OutOfMemory;

            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        try self.expectTagEnd(&node);

        return node;
    }

    fn parseIncrementTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'increment'

        var node = Node.init(self.allocator, .increment_tag);

        if (!self.check(.identifier)) {
            return ParseError.InvalidSyntax;
        }
        const var_name = self.advance();
        node.value = var_name.value;

        try self.expectTagEnd(&node);

        return node;
    }

    fn parseDecrementTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'decrement'

        var node = Node.init(self.allocator, .decrement_tag);

        if (!self.check(.identifier)) {
            return ParseError.InvalidSyntax;
        }
        const var_name = self.advance();
        node.value = var_name.value;

        try self.expectTagEnd(&node);

        return node;
    }

    fn parseTablerowTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'tablerow'

        var node = Node.init(self.allocator, .tablerow_tag);

        // Parse loop variable
        if (!self.check(.identifier)) {
            return ParseError.InvalidSyntax;
        }
        const loop_var = self.advance();
        node.value = loop_var.value;

        // Expect 'in'
        if (!self.check(.kw_in)) {
            return ParseError.InvalidSyntax;
        }
        _ = self.advance();

        // Parse iterable expression
        const iterable = try self.parseExpression();
        node.addChild(iterable) catch return ParseError.OutOfMemory;

        // Parse optional parameters
        while (self.check(.kw_cols) or self.check(.kw_limit) or self.check(.kw_offset)) {
            const param = self.advance();
            var param_node = Node.initWithValue(self.allocator, .expression, param.value);

            if (!self.check(.colon)) {
                return ParseError.InvalidSyntax;
            }
            _ = self.advance();
            const value = try self.parsePrimary();
            param_node.addChild(value) catch return ParseError.OutOfMemory;

            node.addChild(param_node) catch return ParseError.OutOfMemory;
        }

        try self.expectTagEnd(&node);

        // Parse body
        try self.parseTablerowBody(&node);

        return node;
    }

    fn parseTablerowBody(self: *Self, node: *Node) ParseError!void {
        try self.parseBodyUntil(node, .kw_endtablerow, null, null);
    }

    fn parseIncludeTag(self: *Self) ParseError!Node {
        return self.parseIncludeOrRenderTag(.include_tag);
    }

    fn parseRenderTag(self: *Self) ParseError!Node {
        return self.parseIncludeOrRenderTag(.render_tag);
    }

    fn parseIncludeOrRenderTag(self: *Self, node_type: NodeType) ParseError!Node {
        _ = self.advance(); // consume 'include' or 'render'

        var node = Node.init(self.allocator, node_type);

        // Parse template name
        const template = try self.parsePrimary();
        node.addChild(template) catch return ParseError.OutOfMemory;

        // Parse optional 'with' or 'for'
        if (self.check(.kw_with) or self.check(.kw_for)) {
            const is_for = self.check(.kw_for);
            _ = self.advance();

            const val = try self.parsePrimary();
            var binding_node = Node.init(self.allocator, .expression);
            binding_node.value = if (is_for) "for" else "with";
            binding_node.addChild(val) catch return ParseError.OutOfMemory;

            if (self.check(.kw_as)) {
                _ = self.advance();
                if (!self.check(.identifier)) return ParseError.InvalidSyntax;
                binding_node.filter_name = self.advance().value;
            }

            node.addChild(binding_node) catch return ParseError.OutOfMemory;
        }

        // Parse variable assignments
        while (self.check(.comma) or self.check(.identifier)) {
            if (self.check(.comma)) _ = self.advance();
            if (!self.check(.identifier)) break;

            const var_name = self.advance();
            if (!self.check(.colon)) return ParseError.InvalidSyntax;
            _ = self.advance();

            var assign_node = Node.initWithValue(self.allocator, .expression, var_name.value);
            const assign_val = try self.parsePrimary();
            assign_node.addChild(assign_val) catch return ParseError.OutOfMemory;
            node.addChild(assign_node) catch return ParseError.OutOfMemory;
        }

        try self.expectTagEnd(&node);
        return node;
    }

    fn parseRawTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'raw'
        try self.expectTagEndSimple();

        var node = Node.init(self.allocator, .raw_tag);

        // Collect all text until {% endraw %}
        const start = self.pos;
        var end = start;

        while (self.pos < self.tokens.len) {
            const token = self.tokens[self.pos];
            if (token.type == .tag_start or token.type == .tag_start_trim) {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].type == .kw_endraw) {
                    end = self.pos;
                    self.pos += 2; // skip tag_start and endraw
                    try self.expectTagEndSimple();
                    break;
                }
            }
            self.pos += 1;
        }

        // Collect raw content
        var content: std.ArrayList(u8) = .empty;
        for (self.tokens[start..end]) |token| {
            content.appendSlice(self.allocator, token.value) catch return ParseError.OutOfMemory;
        }
        node.value = content.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;

        return node;
    }

    fn parseCommentTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'comment'
        try self.expectTagEndSimple();

        const node = Node.init(self.allocator, .comment_tag);

        // Skip until {% endcomment %}
        while (self.pos < self.tokens.len) {
            const token = self.tokens[self.pos];
            if (token.type == .tag_start or token.type == .tag_start_trim) {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].type == .kw_endcomment) {
                    self.pos += 2;
                    try self.expectTagEndSimple();
                    break;
                }
            }
            self.pos += 1;
        }

        return node;
    }

    fn parseLiquidTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'liquid'

        var node = Node.init(self.allocator, .liquid_tag);

        if (self.check(.liquid_content)) {
            const content_token = self.advance();
            try self.parseLiquidContent(&node, content_token.value);
        }

        try self.expectTagEnd(&node);

        return node;
    }

    fn parseEchoTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'echo'

        var node = Node.init(self.allocator, .echo_tag);

        // Parse expression
        const expr = try self.parseExpression();
        node.addChild(expr) catch return ParseError.OutOfMemory;

        // Parse filters
        while (self.check(.pipe)) {
            _ = self.advance();
            const filter = try self.parseFilter();
            node.addChild(filter) catch return ParseError.OutOfMemory;
        }

        try self.expectTagEnd(&node);

        return node;
    }

    fn parseInlineCommentTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume inline comment token
        var node = Node.init(self.allocator, .comment_tag);
        try self.expectTagEnd(&node);
        return node;
    }

    fn parseLiquidContent(self: *Self, node: *Node, content: []const u8) ParseError!void {
        var builder: std.ArrayList(u8) = .empty;
        var iter = std.mem.splitScalar(u8, content, '\n');

        while (iter.next()) |line_raw| {
            var line = line_raw;
            if (line.len > 0 and line[line.len - 1] == '\r') {
                line = line[0 .. line.len - 1];
            }

            const trimmed_left = std.mem.trimLeft(u8, line, " \t\r");
            if (trimmed_left.len == 0) continue;
            if (trimmed_left[0] == '#') continue;

            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            builder.appendSlice(self.allocator, "{% ") catch return ParseError.OutOfMemory;
            builder.appendSlice(self.allocator, trimmed) catch return ParseError.OutOfMemory;
            builder.appendSlice(self.allocator, " %}") catch return ParseError.OutOfMemory;
        }

        if (builder.items.len == 0) {
            builder.deinit(self.allocator);
            return;
        }

        const temp_template = builder.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        self.liquid_buffers.append(self.allocator, temp_template) catch return ParseError.OutOfMemory;

        var inner_parser = Parser.init(self.allocator, temp_template);
        defer inner_parser.deinit();

        var inner_ast = try inner_parser.parse();

        for (inner_ast.children.items) |child| {
            try node.addChild(child);
        }

        inner_ast.children.items.len = 0;
        inner_ast.deinit();

        try self.takeLiquidBuffers(&inner_parser);
    }

    fn parseBreakTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'break'
        var node = Node.init(self.allocator, .break_tag);
        try self.expectTagEnd(&node);
        return node;
    }

    fn parseContinueTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'continue'
        var node = Node.init(self.allocator, .continue_tag);
        try self.expectTagEnd(&node);
        return node;
    }

    fn parseIfchangedTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'ifchanged'

        var node = Node.init(self.allocator, .ifchanged_tag);
        try self.expectTagEnd(&node);

        // Parse body until endifchanged
        try self.parseIfchangedBody(&node);

        return node;
    }

    fn parseIfchangedBody(self: *Self, node: *Node) ParseError!void {
        try self.parseBodyUntil(node, .kw_endifchanged, null, null);
    }

    fn parseDocTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'doc'
        try self.expectTagEndSimple();

        const node = Node.init(self.allocator, .doc_tag);

        // Skip until {% enddoc %}
        while (self.pos < self.tokens.len) {
            const token = self.tokens[self.pos];
            if (token.type == .tag_start or token.type == .tag_start_trim) {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].type == .kw_enddoc) {
                    self.pos += 2;
                    try self.expectTagEndSimple();
                    break;
                }
            }
            self.pos += 1;
        }

        return node;
    }

    fn expectTagEnd(self: *Self, node: *Node) ParseError!void {
        if (self.check(.tag_end_trim)) {
            node.trim_right = true;
            _ = self.advance();
        } else if (self.check(.tag_end)) {
            _ = self.advance();
        } else {
            return ParseError.InvalidSyntax;
        }
    }

    fn expectTagEndSimple(self: *Self) ParseError!void {
        if (self.check(.tag_end_trim) or self.check(.tag_end)) {
            _ = self.advance();
        } else {
            return ParseError.InvalidSyntax;
        }
    }

    fn takeLiquidBuffers(self: *Self, other: *Self) ParseError!void {
        for (other.liquid_buffers.items) |buf| {
            self.liquid_buffers.append(self.allocator, buf) catch return ParseError.OutOfMemory;
        }
        other.liquid_buffers.clearRetainingCapacity();
    }

    fn peek(self: *Self) Token {
        if (self.pos >= self.tokens.len) {
            return Token.init(.eof, "", 0, 0);
        }
        return self.tokens[self.pos];
    }

    fn advance(self: *Self) Token {
        const token = self.peek();
        if (self.pos < self.tokens.len) {
            self.pos += 1;
        }
        return token;
    }

    fn check(self: *Self, token_type: TokenType) bool {
        return self.peek().type == token_type;
    }

    fn isAtEnd(self: *Self) bool {
        return self.peek().type == .eof;
    }
};

test "parser simple output" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, "{{ 'hello' }}");
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try std.testing.expectEqual(NodeType.root, ast.type);
    try std.testing.expectEqual(@as(usize, 1), ast.children.items.len);
    try std.testing.expectEqual(NodeType.output, ast.children.items[0].type);
}

test "parser variable access" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, "{{ product.title }}");
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try std.testing.expectEqual(NodeType.root, ast.type);
    try std.testing.expectEqual(@as(usize, 1), ast.children.items.len);
}

test "parser assign tag" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, "{% assign x = 5 %}");
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try std.testing.expectEqual(NodeType.root, ast.type);
    try std.testing.expectEqual(@as(usize, 1), ast.children.items.len);
    try std.testing.expectEqual(NodeType.assign_tag, ast.children.items[0].type);
}
