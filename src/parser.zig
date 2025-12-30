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
    literal_empty,
    literal_blank,
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
    inline_comment_tag,
    liquid_tag,
    echo_tag,
    break_tag,
    continue_tag,
    ifchanged_tag,
    doc_tag,
    expression,
    comparison,
    logical,
    invalid_expression,
    filtered_expression,
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
    end_trim_left: bool = false, // For block tags: {%- endXXX %} trims before end tag
    end_trim_right: bool = false, // For block tags: {% endXXX -%} trims after end tag
    invalid_operator: ?[]const u8 = null, // Set when expression has an unknown operator

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

        // Check for empty expression {{}}
        if (self.check(.output_end) or self.check(.output_end_trim)) {
            // Empty expression - create an empty string node
            var empty_node = Node.init(self.allocator, .literal_string);
            empty_node.value = "";
            node.addChild(empty_node) catch return ParseError.OutOfMemory;
        } else {
            // Parse the expression using parsePrimary for lax parsing
            // This way "{{ false a }}" parses "false" and ignores "a"
            const expr = try self.parsePrimary();
            node.addChild(expr) catch return ParseError.OutOfMemory;

            // Parse filters
            while (self.check(.pipe)) {
                _ = self.advance(); // consume pipe
                const filter = try self.parseFilter();
                node.addChild(filter) catch return ParseError.OutOfMemory;
            }

            // Skip any trailing tokens until output end (Ruby Liquid lax parsing)
            // This handles cases like: {{ false a }}, {{ - 'theme.css' - }}, etc.
            while (!self.isAtEnd() and !self.check(.output_end) and !self.check(.output_end_trim)) {
                _ = self.advance();
            }
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
        return self.parseLogical();
    }

    // In Liquid, 'and' and 'or' have the same precedence and are right-associative
    fn parseLogical(self: *Self) ParseError!Node {
        const left = try self.parseComparison();

        if (self.check(.kw_and) or self.check(.kw_or)) {
            const op = self.advance();
            const right = try self.parseLogical(); // Recursive call for right-associativity

            var node = Node.init(self.allocator, .logical);
            node.operator = op.value;
            try node.addChild(left);
            try node.addChild(right);
            return node;
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
            .blank => {
                // Check if followed by [ or . - if so, treat as variable name
                if (self.pos + 1 < self.tokens.len) {
                    const next_type = self.tokens[self.pos + 1].type;
                    if (next_type == .lbracket or next_type == .dot) {
                        return self.parseVariable();
                    }
                }
                _ = self.advance();
                return Node.init(self.allocator, .literal_blank);
            },
            .empty => {
                // Check if followed by [ or . - if so, treat as variable name
                if (self.pos + 1 < self.tokens.len) {
                    const next_type = self.tokens[self.pos + 1].type;
                    if (next_type == .lbracket or next_type == .dot) {
                        return self.parseVariable();
                    }
                }
                _ = self.advance();
                return Node.init(self.allocator, .literal_empty);
            },
            .identifier => {
                return self.parseVariable();
            },
            // Keywords can be used as variable names in expression context
            .kw_include, .kw_render, .kw_tablerow, .kw_cycle, .kw_increment, .kw_decrement, .kw_ifchanged, .kw_echo, .kw_liquid => {
                return self.parseVariable();
            },
            .lparen => {
                // Could be a range, grouped expression, or expression with filters
                _ = self.advance(); // consume (

                // First, try to parse as a primary to check for range
                var start = try self.parsePrimary();

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

                // Handle filters inside parentheses (e.g., ('X' | downcase))
                if (self.check(.pipe)) {
                    // Wrap the primary in a filtered_expression node
                    var filtered = Node.init(self.allocator, .filtered_expression);
                    filtered.addChild(start) catch return ParseError.OutOfMemory;

                    while (self.check(.pipe)) {
                        _ = self.advance();
                        const filter = try self.parseFilter();
                        filtered.addChild(filter) catch return ParseError.OutOfMemory;
                    }
                    start = filtered;
                }

                // Check for comparison or logical operators - this handles grouped expressions like (a == b and c == d)
                const is_comparison = switch (self.peek().type) {
                    .eq, .ne, .lt, .gt, .le, .ge, .kw_contains => true,
                    else => false,
                };

                if (is_comparison) {
                    const op = self.advance();
                    const right = try self.parsePrimary();

                    var comp_node = Node.init(self.allocator, .comparison);
                    comp_node.operator = op.value;
                    try comp_node.addChild(start);
                    try comp_node.addChild(right);
                    start = comp_node;

                    // Now check for logical operators
                    while (self.check(.kw_and) or self.check(.kw_or)) {
                        const log_op = self.advance();
                        // Parse the next comparison
                        const next_left = try self.parsePrimary();

                        var right_node: Node = undefined;
                        const is_next_comp = switch (self.peek().type) {
                            .eq, .ne, .lt, .gt, .le, .ge, .kw_contains => true,
                            else => false,
                        };

                        if (is_next_comp) {
                            const next_op = self.advance();
                            const next_right = try self.parsePrimary();
                            right_node = Node.init(self.allocator, .comparison);
                            right_node.operator = next_op.value;
                            try right_node.addChild(next_left);
                            try right_node.addChild(next_right);
                        } else {
                            right_node = next_left;
                        }

                        var log_node = Node.init(self.allocator, .logical);
                        log_node.operator = log_op.value;
                        try log_node.addChild(start);
                        try log_node.addChild(right_node);
                        start = log_node;
                    }
                } else if (self.check(.kw_and) or self.check(.kw_or)) {
                    // Logical without comparison first (e.g., (a and b))
                    while (self.check(.kw_and) or self.check(.kw_or)) {
                        const log_op = self.advance();
                        const right = try self.parsePrimary();

                        var log_node = Node.init(self.allocator, .logical);
                        log_node.operator = log_op.value;
                        try log_node.addChild(start);
                        try log_node.addChild(right);
                        start = log_node;
                    }
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
            // Use token value for identifiers and keywords used as variable names
            const var_name = if (token.value.len > 0) token.value else switch (token.type) {
                .kw_include => "include",
                .kw_render => "render",
                .kw_tablerow => "tablerow",
                .kw_cycle => "cycle",
                .kw_increment => "increment",
                .kw_decrement => "decrement",
                .kw_ifchanged => "ifchanged",
                .kw_echo => "echo",
                .kw_liquid => "liquid",
                else => "",
            };
            node = Node.initWithValue(self.allocator, .variable, var_name);
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
            } else if (self.check(.assign) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].type == .gt) {
                // Ruby Liquid lax mode: foo=>bar is treated as foo.bar (hash rocket as property access)
                _ = self.advance(); // consume =
                _ = self.advance(); // consume >
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

        // Ruby Liquid lax mode: skip unexpected characters between filter name and colon
        // e.g., split$$$:' ' should parse as split:' '
        while (!self.isAtEnd() and !self.check(.colon) and !self.check(.pipe) and
            !self.check(.output_end) and !self.check(.output_end_trim) and
            !self.check(.tag_end) and !self.check(.tag_end_trim) and
            !self.check(.rparen))
        {
            _ = self.advance();
        }

        // Parse filter arguments
        if (self.check(.colon)) {
            _ = self.advance(); // consume :

            // Parse first argument
            const arg = try self.parseFilterArg();
            node.filter_args.?.append(self.allocator, arg) catch return ParseError.OutOfMemory;

            // Ruby Liquid lax mode: skip unexpected tokens after argument
            // e.g., split:"t"" should parse as split:"t" and skip the extra "
            while (!self.isAtEnd() and !self.check(.comma) and !self.check(.pipe) and
                !self.check(.output_end) and !self.check(.output_end_trim) and
                !self.check(.tag_end) and !self.check(.tag_end_trim) and
                !self.check(.rparen))
            {
                _ = self.advance();
            }

            // Parse additional arguments
            while (self.check(.comma)) {
                _ = self.advance(); // consume ,
                const next_arg = try self.parseFilterArg();
                node.filter_args.?.append(self.allocator, next_arg) catch return ParseError.OutOfMemory;

                // Skip unexpected tokens after argument
                while (!self.isAtEnd() and !self.check(.comma) and !self.check(.pipe) and
                    !self.check(.output_end) and !self.check(.output_end_trim) and
                    !self.check(.tag_end) and !self.check(.tag_end_trim) and
                    !self.check(.rparen))
                {
                    _ = self.advance();
                }
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
        var condition = try self.parseExpression();

        // Check for leftover tokens (unknown operator situation)
        // In lax mode, we skip to tag end and record the invalid operator
        if (!self.check(.tag_end) and !self.check(.tag_end_trim)) {
            // Record the unknown operator token's value
            const bad_token = self.peek();
            condition.invalid_operator = bad_token.value;
            // Skip to tag end
            try self.skipToTagEnd(&node);
        } else {
            try self.expectTagEnd(&node);
        }

        node.addChild(condition) catch return ParseError.OutOfMemory;

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
                const start_token = self.advance(); // consume {%
                const tag_trim_left = start_token.type == .tag_start_trim;

                const tag_token = self.peek();

                if (tag_token.type == .kw_elsif) {
                    _ = self.advance(); // consume 'elsif'
                    var elsif_node = Node.init(self.allocator, .elsif_branch);
                    elsif_node.trim_left = tag_trim_left;
                    var elsif_cond = try self.parseExpression();

                    // Check for leftover tokens (unknown operator situation)
                    if (!self.check(.tag_end) and !self.check(.tag_end_trim)) {
                        const bad_token = self.peek();
                        elsif_cond.invalid_operator = bad_token.value;
                        try self.skipToTagEnd(&elsif_node);
                    } else {
                        try self.expectTagEnd(&elsif_node);
                    }

                    elsif_node.addChild(elsif_cond) catch return ParseError.OutOfMemory;
                    try self.parseIfBody(&elsif_node);
                    node.addChild(elsif_node) catch return ParseError.OutOfMemory;
                    return;
                } else if (tag_token.type == .kw_else) {
                    _ = self.advance(); // consume 'else'
                    var else_node = Node.init(self.allocator, .else_branch);
                    else_node.trim_left = tag_trim_left;
                    // Skip any tokens until tag end (else expressions are ignored in Liquid)
                    try self.skipToTagEnd(&else_node);
                    try self.parseIfBody(&else_node);
                    node.addChild(else_node) catch return ParseError.OutOfMemory;
                    return;
                } else if (tag_token.type == .kw_endif) {
                    _ = self.advance(); // consume 'endif'
                    // Apply end_trim_left from {%- endif - trim trailing ws in output during render
                    node.end_trim_left = tag_trim_left;
                    try self.expectEndTagEnd(node);
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
                    try self.expectEndTagEnd(node);
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
        // Parse body nodes until elsif, else, or endunless
        while (!self.isAtEnd()) {
            const token = self.peek();

            if (token.type == .text) {
                const text_node = try self.parseText();
                node.addChild(text_node) catch return ParseError.OutOfMemory;
            } else if (token.type == .output_start or token.type == .output_start_trim) {
                const output_node = try self.parseOutput();
                node.addChild(output_node) catch return ParseError.OutOfMemory;
            } else if (token.type == .tag_start or token.type == .tag_start_trim) {
                const start_token = self.advance(); // consume {%
                const tag_trim_left = start_token.type == .tag_start_trim;

                const tag_token = self.peek();

                if (tag_token.type == .kw_elsif) {
                    _ = self.advance(); // consume 'elsif'
                    var elsif_node = Node.init(self.allocator, .elsif_branch);
                    var elsif_cond = try self.parseExpression();

                    // Check for leftover tokens (unknown operator situation)
                    if (!self.check(.tag_end) and !self.check(.tag_end_trim)) {
                        const bad_token = self.peek();
                        elsif_cond.invalid_operator = bad_token.value;
                        try self.skipToTagEnd(&elsif_node);
                    } else {
                        try self.expectTagEnd(&elsif_node);
                    }

                    elsif_node.addChild(elsif_cond) catch return ParseError.OutOfMemory;
                    try self.parseUnlessBody(&elsif_node);
                    node.addChild(elsif_node) catch return ParseError.OutOfMemory;
                    return;
                } else if (tag_token.type == .kw_else) {
                    _ = self.advance(); // consume 'else'
                    var else_node = Node.init(self.allocator, .else_branch);
                    // Skip any tokens until tag end (else expressions are ignored in Liquid)
                    try self.skipToTagEnd(&else_node);
                    try self.parseUnlessBody(&else_node);
                    node.addChild(else_node) catch return ParseError.OutOfMemory;
                    return;
                } else if (tag_token.type == .kw_endunless) {
                    _ = self.advance(); // consume 'endunless'
                    node.end_trim_left = tag_trim_left;
                    try self.expectEndTagEnd(node);
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

        // Skip optional comma after iterable
        if (self.check(.comma)) {
            _ = self.advance();
        }

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

            // Skip optional comma between parameters
            if (self.check(.comma)) {
                _ = self.advance();
            }
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

        // Parse variable name (can be identifier or integer in Ruby Liquid)
        if (!self.check(.identifier) and !self.check(.integer)) {
            return ParseError.InvalidSyntax;
        }
        const var_name = self.advance();
        node.value = var_name.value;

        // Expect '='
        if (!self.check(.assign)) {
            return ParseError.InvalidSyntax;
        }
        _ = self.advance();

        // Parse value expression using parsePrimary for lax parsing
        const value = try self.parsePrimary();
        node.addChild(value) catch return ParseError.OutOfMemory;

        // Parse filters
        while (self.check(.pipe)) {
            _ = self.advance();
            const filter = try self.parseFilter();
            node.addChild(filter) catch return ParseError.OutOfMemory;
        }

        // Skip any trailing tokens until tag end (Ruby Liquid lax parsing)
        // This handles cases like: assign foo = false a, etc.
        while (!self.isAtEnd() and !self.check(.tag_end) and !self.check(.tag_end_trim)) {
            _ = self.advance();
        }

        try self.expectTagEnd(&node);

        return node;
    }

    fn parseCaptureTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'capture'

        var node = Node.init(self.allocator, .capture_tag);

        // Parse variable name (can be identifier, integer, or string in Ruby Liquid)
        if (!self.check(.identifier) and !self.check(.integer) and !self.check(.string)) {
            return ParseError.InvalidSyntax;
        }
        const var_name = self.advance();
        // For string variable names, strip the quotes
        if (var_name.type == .string) {
            const val = var_name.value;
            if (val.len >= 2 and (val[0] == '"' or val[0] == '\'')) {
                node.value = val[1 .. val.len - 1];
            } else {
                node.value = val;
            }
        } else {
            node.value = var_name.value;
        }

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

        // Parse expression to match - use parsePrimary for lax parsing
        // This way "case 1 bar" parses "1" and ignores "bar"
        const expr = try self.parsePrimary();
        node.addChild(expr) catch return ParseError.OutOfMemory;

        // Skip any trailing tokens until tag end (Ruby Liquid lax parsing)
        // This handles cases like: case 1 bar, case foo=>bar, etc.
        while (!self.isAtEnd() and !self.check(.tag_end) and !self.check(.tag_end_trim)) {
            _ = self.advance();
        }

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
                const trim_left = token.type == .tag_start_trim;
                _ = self.advance();

                const tag_token = self.peek();

                if (tag_token.type == .kw_when) {
                    _ = self.advance();
                    var when_node = Node.init(self.allocator, .when_branch);
                    when_node.trim_left = trim_left;

                    // Parse when values (can be comma-separated or separated by 'or')
                    // Note: 'and' in Ruby Liquid causes everything after it to be ignored
                    const when_val = try self.parsePrimary();
                    when_node.addChild(when_val) catch return ParseError.OutOfMemory;

                    while (self.check(.comma) or self.check(.kw_or)) {
                        _ = self.advance();
                        // Handle trailing 'or' after comma (e.g., "4, or 6")
                        if (self.check(.kw_or)) {
                            _ = self.advance();
                        }
                        // Handle trailing comma before tag end
                        if (self.check(.tag_end) or self.check(.tag_end_trim)) {
                            break;
                        }
                        const next_val = try self.parsePrimary();
                        when_node.addChild(next_val) catch return ParseError.OutOfMemory;
                    }

                    // If 'and' appears or any other token that's not tag_end, skip until tag end (Ruby Liquid lax parsing)
                    // This handles cases like: when 1 bar, when foo=>bar, etc.
                    while (!self.isAtEnd() and !self.check(.tag_end) and !self.check(.tag_end_trim)) {
                        _ = self.advance();
                    }

                    try self.expectTagEnd(&when_node);
                    try self.parseWhenBody(&when_node);
                    node.addChild(when_node) catch return ParseError.OutOfMemory;
                } else if (tag_token.type == .kw_else) {
                    _ = self.advance();
                    var else_node = Node.init(self.allocator, .else_branch);
                    else_node.trim_left = trim_left;
                    try self.expectTagEnd(&else_node);
                    try self.parseWhenBody(&else_node);
                    node.addChild(else_node) catch return ParseError.OutOfMemory;
                } else if (tag_token.type == .kw_endcase) {
                    _ = self.advance();
                    // Store end_trim_left for endcase
                    if (trim_left) {
                        node.end_trim_left = true;
                    }
                    try self.expectEndTagEnd(node);
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

        // Check for optional group name (can be string or identifier followed by colon)
        if (self.check(.string)) {
            const group = self.advance();
            if (self.check(.colon)) {
                node.value = group.value;
                _ = self.advance(); // consume :
            } else {
                // It's a cycle value, not a group - add it and check for comma
                const val_node = Node.initWithValue(self.allocator, .literal_string, group.value);
                node.addChild(val_node) catch return ParseError.OutOfMemory;
                // If there's a comma, consume it and continue parsing values
                if (self.check(.comma)) {
                    _ = self.advance();
                }
            }
        } else if (self.check(.identifier)) {
            // Look ahead to see if this is a group name (identifier followed by colon)
            if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].type == .colon) {
                const group = self.advance();
                node.value = group.value;
                _ = self.advance(); // consume :
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
        // Check if {% raw -%} to capture trim_right for content
        const opening_trim_right = self.check(.tag_end_trim);
        try self.expectTagEndSimple();

        var node = Node.init(self.allocator, .raw_tag);
        node.trim_right = opening_trim_right; // Will trim leading ws from raw content

        // The lexer now provides a raw_content token with the exact content
        if (self.pos < self.tokens.len and self.tokens[self.pos].type == .raw_content) {
            node.value = self.tokens[self.pos].value;
            _ = self.advance(); // consume raw_content
        } else {
            node.value = "";
        }

        // Now expect {% endraw %} or {%- endraw -%}
        if (self.pos < self.tokens.len and
            (self.tokens[self.pos].type == .tag_start or self.tokens[self.pos].type == .tag_start_trim))
        {
            const endraw_trim_left = self.tokens[self.pos].type == .tag_start_trim;
            _ = self.advance(); // consume tag_start
            if (self.pos < self.tokens.len and self.tokens[self.pos].type == .kw_endraw) {
                _ = self.advance(); // consume endraw
                // Check for -%} at the end
                node.end_trim_left = endraw_trim_left; // {%- endraw trims before
                if (self.check(.tag_end_trim)) {
                    node.end_trim_right = true; // endraw -%} trims after
                    _ = self.advance();
                } else if (self.check(.tag_end)) {
                    _ = self.advance();
                }
            }
        }

        return node;
    }

    fn parseCommentTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume 'comment'

        var node = Node.init(self.allocator, .comment_tag);

        // Skip any content after 'comment' until tag end (for inline comment syntax inside liquid tag)
        while (!self.isAtEnd() and !self.check(.tag_end) and !self.check(.tag_end_trim)) {
            _ = self.advance();
        }
        // Track {%- comment -%} opening tag's trim_right
        if (self.check(.tag_end_trim)) {
            node.trim_right = true;
            _ = self.advance();
        } else if (self.check(.tag_end)) {
            _ = self.advance();
        } else {
            return ParseError.InvalidSyntax;
        }

        // Skip until matching {% endcomment %}, tracking nesting and raw blocks
        var nesting_depth: usize = 1;
        var in_raw: bool = false;
        while (self.pos < self.tokens.len and nesting_depth > 0) {
            const token = self.tokens[self.pos];
            if (token.type == .tag_start or token.type == .tag_start_trim) {
                if (self.pos + 1 < self.tokens.len) {
                    const next_token = self.tokens[self.pos + 1];
                    if (next_token.type == .kw_raw) {
                        in_raw = true;
                    } else if (next_token.type == .kw_endraw) {
                        in_raw = false;
                    } else if (!in_raw) {
                        if (next_token.type == .kw_comment) {
                            nesting_depth += 1;
                        } else if (next_token.type == .kw_endcomment) {
                            nesting_depth -= 1;
                            if (nesting_depth == 0) {
                                // Track {%- endcomment for end_trim_left
                                if (token.type == .tag_start_trim) {
                                    node.end_trim_left = true;
                                }
                                self.pos += 2;
                                // Skip any content after endcomment and find tag end
                                while (!self.isAtEnd() and !self.check(.tag_end) and !self.check(.tag_end_trim)) {
                                    _ = self.advance();
                                }
                                // Track endcomment -%} for end_trim_right
                                if (self.check(.tag_end_trim)) {
                                    node.end_trim_right = true;
                                    _ = self.advance();
                                } else if (self.check(.tag_end)) {
                                    _ = self.advance();
                                } else {
                                    return ParseError.InvalidSyntax;
                                }
                                break;
                            }
                        }
                    }
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

        // Parse expression if present (echo with no args outputs nothing)
        if (!self.check(.tag_end) and !self.check(.tag_end_trim)) {
            const expr = try self.parseExpression();
            node.addChild(expr) catch return ParseError.OutOfMemory;

            // Parse filters
            while (self.check(.pipe)) {
                _ = self.advance();
                const filter = try self.parseFilter();
                node.addChild(filter) catch return ParseError.OutOfMemory;
            }
        }

        try self.expectTagEnd(&node);

        return node;
    }

    fn parseInlineCommentTag(self: *Self) ParseError!Node {
        _ = self.advance(); // consume inline comment token
        var node = Node.init(self.allocator, .inline_comment_tag);
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

        var node = Node.init(self.allocator, .doc_tag);

        // Track {% doc -%} opening tag's trim_right
        if (self.check(.tag_end_trim)) {
            node.trim_right = true;
            _ = self.advance();
        } else if (self.check(.tag_end)) {
            _ = self.advance();
        } else {
            return ParseError.InvalidSyntax;
        }

        // Skip until {% enddoc %} or {%- enddoc -%}
        while (self.pos < self.tokens.len) {
            const token = self.tokens[self.pos];
            if (token.type == .tag_start or token.type == .tag_start_trim) {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].type == .kw_enddoc) {
                    // Track {%- enddoc for end_trim_left
                    if (token.type == .tag_start_trim) {
                        node.end_trim_left = true;
                    }
                    self.pos += 2;
                    // Skip any content after enddoc (e.g., {% enddoc xyz %})
                    while (!self.isAtEnd() and !self.check(.tag_end) and !self.check(.tag_end_trim)) {
                        _ = self.advance();
                    }
                    // Track enddoc -%} for end_trim_right
                    if (self.check(.tag_end_trim)) {
                        node.end_trim_right = true;
                        _ = self.advance();
                    } else if (self.check(.tag_end)) {
                        _ = self.advance();
                    } else {
                        return ParseError.InvalidSyntax;
                    }
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

    /// Skip any tokens until we reach a tag_end or tag_end_trim, then consume it
    fn skipToTagEndSimple(self: *Self) ParseError!void {
        while (!self.isAtEnd() and !self.check(.tag_end) and !self.check(.tag_end_trim)) {
            _ = self.advance();
        }
        if (self.check(.tag_end_trim) or self.check(.tag_end)) {
            _ = self.advance();
        } else {
            return ParseError.InvalidSyntax;
        }
    }

    /// Like expectTagEnd but sets end_trim_right (for closing tags like endif, endfor, etc.)
    fn expectEndTagEnd(self: *Self, node: *Node) ParseError!void {
        if (self.check(.tag_end_trim)) {
            node.end_trim_right = true;
            _ = self.advance();
        } else if (self.check(.tag_end)) {
            _ = self.advance();
        } else {
            return ParseError.InvalidSyntax;
        }
    }

    fn skipToTagEnd(self: *Self, node: *Node) ParseError!void {
        // Skip any tokens until we reach tag_end or tag_end_trim
        while (!self.isAtEnd() and !self.check(.tag_end) and !self.check(.tag_end_trim)) {
            _ = self.advance();
        }
        try self.expectTagEnd(node);
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
