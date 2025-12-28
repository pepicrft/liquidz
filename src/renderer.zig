//! Renderer for Liquid templates.
//! Takes an AST and a context, and produces the rendered output.

const std = @import("std");
const Allocator = std.mem.Allocator;
const parser_mod = @import("parser.zig");
const Node = parser_mod.Node;
const NodeType = parser_mod.NodeType;
const value_mod = @import("value.zig");
const Value = value_mod.Value;

pub const RenderError = error{
    OutOfMemory,
    InvalidOperation,
    UndefinedVariable,
    TypeError,
    BreakLoop,
    ContinueLoop,
};

pub const Renderer = struct {
    allocator: Allocator,
    context: Value,
    output: std.ArrayList(u8),
    local_vars: std.StringHashMap(Value),
    counters: std.StringHashMap(i64),
    cycle_indices: std.StringHashMap(usize),
    continue_offsets: std.StringHashMap(usize),
    forloop_stack: std.ArrayList(ForloopInfo),
    tablerow_stack: std.ArrayList(TablerowInfo),
    scratch: std.heap.ArenaAllocator,

    const Self = @This();

    const ForloopInfo = struct {
        index: usize,
        index0: usize,
        length: usize,
        first: bool,
        last: bool,
        rindex: usize,
        rindex0: usize,
    };

    const TablerowInfo = struct {
        col: usize,
        col0: usize,
        col_first: bool,
        col_last: bool,
        row: usize,
        index: usize,
        index0: usize,
        length: usize,
        first: bool,
        last: bool,
        rindex: usize,
        rindex0: usize,
    };

    const LocalOverride = struct {
        name: []const u8,
        value: Value,
    };

    const LocalBackup = struct {
        name: []const u8,
        had: bool,
        value: Value,
    };

    pub fn init(allocator: Allocator, context: Value) Self {
        const scratch = std.heap.ArenaAllocator.init(allocator);
        return .{
            .allocator = allocator,
            .context = context,
            .output = .empty,
            .local_vars = std.StringHashMap(Value).init(allocator),
            .counters = std.StringHashMap(i64).init(allocator),
            .cycle_indices = std.StringHashMap(usize).init(allocator),
            .continue_offsets = std.StringHashMap(usize).init(allocator),
            .forloop_stack = .empty,
            .tablerow_stack = .empty,
            .scratch = scratch,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
        self.local_vars.deinit();
        self.counters.deinit();
        self.cycle_indices.deinit();
        var cont_it = self.continue_offsets.iterator();
        while (cont_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.continue_offsets.deinit();
        self.forloop_stack.deinit(self.allocator);
        self.tablerow_stack.deinit(self.allocator);
        self.scratch.deinit();
    }

    fn workAllocator(self: *Self) Allocator {
        return self.scratch.allocator();
    }

    fn templatesValue(self: *Self) ?Value {
        if (self.local_vars.get("__templates")) |val| return val;
        if (self.local_vars.get("templates")) |val| return val;
        if (self.context.get("__templates")) |val| return val;
        if (self.context.get("templates")) |val| return val;
        return null;
    }

    fn resolveTemplateSource(self: *Self, name: []const u8) ?[]const u8 {
        const templates = self.templatesValue() orelse return null;
        return switch (templates) {
            .object => |obj| if (obj.get(name)) |val| switch (val) {
                .string => |s| s,
                else => null,
            } else null,
            else => null,
        };
    }

    fn applyOverrides(self: *Self, overrides: []const LocalOverride, backups: *std.ArrayList(LocalBackup)) RenderError!void {
        for (overrides) |entry| {
            if (self.local_vars.get(entry.name)) |old| {
                backups.append(self.allocator, .{ .name = entry.name, .had = true, .value = old }) catch return RenderError.OutOfMemory;
            } else {
                backups.append(self.allocator, .{ .name = entry.name, .had = false, .value = Value.initNil() }) catch return RenderError.OutOfMemory;
            }
            self.local_vars.put(entry.name, entry.value) catch return RenderError.OutOfMemory;
        }
    }

    fn restoreOverrides(self: *Self, backups: *std.ArrayList(LocalBackup)) void {
        var i = backups.items.len;
        while (i > 0) {
            i -= 1;
            const entry = backups.items[i];
            if (entry.had) {
                self.local_vars.put(entry.name, entry.value) catch {};
            } else {
                _ = self.local_vars.fetchRemove(entry.name);
            }
        }
        backups.deinit(self.allocator);
    }

    fn buildContinueKey(self: *Self, node: Node) RenderError![]const u8 {
        var list: std.ArrayList(u8) = .empty;
        try self.appendNodeKey(&list, node);
        return list.toOwnedSlice(self.allocator) catch return RenderError.OutOfMemory;
    }

    fn appendNodeKey(self: *Self, list: *std.ArrayList(u8), node: Node) RenderError!void {
        switch (node.type) {
            .variable => if (node.value) |v| {
                list.appendSlice(self.allocator, v) catch return RenderError.OutOfMemory;
            },
            .literal_string,
            .literal_integer,
            .literal_float,
            .literal_bool,
            .literal_nil,
            => if (node.value) |v| {
                list.appendSlice(self.allocator, v) catch return RenderError.OutOfMemory;
            } else {
                list.appendSlice(self.allocator, "nil") catch return RenderError.OutOfMemory;
            },
            .property_access => {
                if (node.children.items.len > 0) {
                    try self.appendNodeKey(list, node.children.items[0]);
                }
                list.append(self.allocator, '.') catch return RenderError.OutOfMemory;
                if (node.value) |v| {
                    list.appendSlice(self.allocator, v) catch return RenderError.OutOfMemory;
                }
            },
            .index_access => {
                if (node.children.items.len > 0) {
                    try self.appendNodeKey(list, node.children.items[0]);
                }
                list.append(self.allocator, '[') catch return RenderError.OutOfMemory;
                if (node.children.items.len > 1) {
                    try self.appendNodeKey(list, node.children.items[1]);
                }
                list.append(self.allocator, ']') catch return RenderError.OutOfMemory;
            },
            .range => {
                list.appendSlice(self.allocator, "(") catch return RenderError.OutOfMemory;
                if (node.children.items.len > 0) {
                    try self.appendNodeKey(list, node.children.items[0]);
                }
                list.appendSlice(self.allocator, "..") catch return RenderError.OutOfMemory;
                if (node.children.items.len > 1) {
                    try self.appendNodeKey(list, node.children.items[1]);
                }
                list.appendSlice(self.allocator, ")") catch return RenderError.OutOfMemory;
            },
            else => {
                list.appendSlice(self.allocator, "<expr>") catch return RenderError.OutOfMemory;
            },
        }
    }

    pub fn render(self: *Self, ast: Node) ![]const u8 {
        _ = self.scratch.reset(.retain_capacity);
        try self.renderNode(ast);
        return self.output.toOwnedSlice(self.allocator);
    }

    fn renderNode(self: *Self, node: Node) RenderError!void {
        switch (node.type) {
            .root => {
                for (node.children.items) |child| {
                    try self.renderNode(child);
                }
            },
            .text => {
                if (node.value) |v| {
                    self.output.appendSlice(self.allocator, v) catch return RenderError.OutOfMemory;
                }
            },
            .output => {
                try self.renderOutput(node);
            },
            .if_tag => {
                try self.renderIfTag(node);
            },
            .unless_tag => {
                try self.renderUnlessTag(node);
            },
            .for_tag => {
                self.renderForTag(node) catch |err| {
                    if (err == RenderError.BreakLoop or err == RenderError.ContinueLoop) {
                        // These should be handled within the for loop
                        return;
                    }
                    return err;
                };
            },
            .assign_tag => {
                try self.renderAssignTag(node);
            },
            .capture_tag => {
                try self.renderCaptureTag(node);
            },
            .case_tag => {
                try self.renderCaseTag(node);
            },
            .cycle_tag => {
                try self.renderCycleTag(node);
            },
            .increment_tag => {
                try self.renderIncrementTag(node);
            },
            .decrement_tag => {
                try self.renderDecrementTag(node);
            },
            .tablerow_tag => {
                try self.renderTablerowTag(node);
            },
            .include_tag => {
                try self.renderIncludeTag(node);
            },
            .render_tag => {
                try self.renderRenderTag(node);
            },
            .echo_tag => {
                try self.renderEchoTag(node);
            },
            .liquid_tag => {
                for (node.children.items) |child| {
                    try self.renderNode(child);
                }
            },
            .raw_tag => {
                if (node.value) |v| {
                    self.output.appendSlice(self.allocator, v) catch return RenderError.OutOfMemory;
                }
            },
            .comment_tag, .doc_tag => {
                // Comments produce no output
            },
            .break_tag => {
                return RenderError.BreakLoop;
            },
            .continue_tag => {
                return RenderError.ContinueLoop;
            },
            .ifchanged_tag => {
                try self.renderIfchangedTag(node);
            },
            else => {},
        }
    }

    fn renderOutput(self: *Self, node: Node) RenderError!void {
        if (node.children.items.len == 0) return;

        // First child is the expression
        var value = try self.evaluateNode(node.children.items[0]);

        // Apply filters
        for (node.children.items[1..]) |child| {
            if (child.type == .filter) {
                value = try self.applyFilter(value, child);
            }
        }

        // Convert to string and append
        const str = value.toString(self.allocator) catch return RenderError.OutOfMemory;
        defer switch (value) {
            .integer, .float, .array => self.allocator.free(str),
            else => {},
        };
        self.output.appendSlice(self.allocator, str) catch return RenderError.OutOfMemory;
    }

    fn evaluateNode(self: *Self, node: Node) RenderError!Value {
        return switch (node.type) {
            .literal_string => Value.initString(node.value orelse ""),
            .literal_integer => blk: {
                const val = std.fmt.parseInt(i64, node.value orelse "0", 10) catch 0;
                break :blk Value.initInt(val);
            },
            .literal_float => blk: {
                const val = std.fmt.parseFloat(f64, node.value orelse "0") catch 0.0;
                break :blk Value.initFloat(val);
            },
            .literal_bool => Value.initBool(std.mem.eql(u8, node.value orelse "false", "true")),
            .literal_nil => Value.initNil(),
            .variable => self.resolveVariable(node.value orelse ""),
            .property_access => blk: {
                if (node.children.items.len == 0) break :blk Value.initNil();
                const base = try self.evaluateNode(node.children.items[0]);
                const prop = node.value orelse "";

                // Special handling for forloop.parentloop
                if (std.mem.eql(u8, prop, "parentloop") and base == .object) {
                    if (base.object.get("_parentloop_index")) |parent_idx| {
                        if (parent_idx == .integer) {
                            break :blk self.buildForloopObject(@intCast(parent_idx.integer));
                        }
                    }
                }

                break :blk base.get(prop) orelse Value.initNil();
            },
            .index_access => blk: {
                if (node.children.items.len < 2) break :blk Value.initNil();
                const base = try self.evaluateNode(node.children.items[0]);
                const index = try self.evaluateNode(node.children.items[1]);

                break :blk switch (index) {
                    .integer => |i| base.getIndex(i) orelse Value.initNil(),
                    .string => |s| base.get(s) orelse Value.initNil(),
                    else => Value.initNil(),
                };
            },
            .range => blk: {
                if (node.children.items.len < 2) break :blk Value.initNil();
                const start_val = try self.evaluateNode(node.children.items[0]);
                const end_val = try self.evaluateNode(node.children.items[1]);

                const start = switch (start_val) {
                    .integer => |i| i,
                    .float => |f| @as(i64, @intFromFloat(f)),
                    else => 0,
                };
                const end = switch (end_val) {
                    .integer => |i| i,
                    .float => |f| @as(i64, @intFromFloat(f)),
                    else => 0,
                };

                var arr: std.ArrayList(Value) = .empty;
                var i = start;
                while (i <= end) : (i += 1) {
                    arr.append(self.workAllocator(), Value.initInt(i)) catch return RenderError.OutOfMemory;
                }
                break :blk Value.initArray(arr.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
            },
            .comparison => try self.evaluateComparison(node),
            .logical => try self.evaluateLogical(node),
            else => Value.initNil(),
        };
    }

    fn resolveVariable(self: *Self, name: []const u8) Value {
        // Check forloop first
        if (std.mem.eql(u8, name, "forloop")) {
            if (self.forloop_stack.items.len > 0) {
                return self.buildForloopObject(self.forloop_stack.items.len - 1);
            }
        }

        if (std.mem.eql(u8, name, "tablerowloop")) {
            if (self.tablerow_stack.items.len > 0) {
                const info = self.tablerow_stack.items[self.tablerow_stack.items.len - 1];
                var obj = Value.initObject(self.allocator);
                obj.object.put("col", Value.initInt(@intCast(info.col))) catch {};
                obj.object.put("col0", Value.initInt(@intCast(info.col0))) catch {};
                obj.object.put("col_first", Value.initBool(info.col_first)) catch {};
                obj.object.put("col_last", Value.initBool(info.col_last)) catch {};
                obj.object.put("row", Value.initInt(@intCast(info.row))) catch {};
                obj.object.put("index", Value.initInt(@intCast(info.index))) catch {};
                obj.object.put("index0", Value.initInt(@intCast(info.index0))) catch {};
                obj.object.put("first", Value.initBool(info.first)) catch {};
                obj.object.put("last", Value.initBool(info.last)) catch {};
                obj.object.put("length", Value.initInt(@intCast(info.length))) catch {};
                obj.object.put("rindex", Value.initInt(@intCast(info.rindex))) catch {};
                obj.object.put("rindex0", Value.initInt(@intCast(info.rindex0))) catch {};
                return obj;
            }
        }

        // Check local variables
        if (self.local_vars.get(name)) |val| {
            return val;
        }

        // Check context
        return self.context.get(name) orelse Value.initNil();
    }

    /// Build a forloop object for the given stack index
    fn buildForloopObject(self: *Self, stack_index: usize) Value {
        if (stack_index >= self.forloop_stack.items.len) {
            return Value.initNil();
        }

        const info = self.forloop_stack.items[stack_index];
        var obj = Value.initObject(self.allocator);
        obj.object.put("index", Value.initInt(@intCast(info.index))) catch {};
        obj.object.put("index0", Value.initInt(@intCast(info.index0))) catch {};
        obj.object.put("first", Value.initBool(info.first)) catch {};
        obj.object.put("last", Value.initBool(info.last)) catch {};
        obj.object.put("length", Value.initInt(@intCast(info.length))) catch {};
        obj.object.put("rindex", Value.initInt(@intCast(info.rindex))) catch {};
        obj.object.put("rindex0", Value.initInt(@intCast(info.rindex0))) catch {};

        // Add parentloop reference if there's a parent loop
        if (stack_index > 0) {
            // Store the parent stack index as a special property
            // We'll need to handle this in property access
            obj.object.put("_parentloop_index", Value.initInt(@intCast(stack_index - 1))) catch {};
        }

        return obj;
    }

    fn evaluateComparison(self: *Self, node: Node) RenderError!Value {
        if (node.children.items.len < 2) return Value.initBool(false);

        const left = try self.evaluateNode(node.children.items[0]);
        const right = try self.evaluateNode(node.children.items[1]);
        const op = node.operator orelse "==";

        const result = if (std.mem.eql(u8, op, "=="))
            left.eql(right)
        else if (std.mem.eql(u8, op, "!=") or std.mem.eql(u8, op, "<>"))
            !left.eql(right)
        else if (std.mem.eql(u8, op, "<"))
            self.compareLess(left, right)
        else if (std.mem.eql(u8, op, ">"))
            self.compareGreater(left, right)
        else if (std.mem.eql(u8, op, "<="))
            self.compareLessOrEqual(left, right)
        else if (std.mem.eql(u8, op, ">="))
            self.compareGreaterOrEqual(left, right)
        else if (std.mem.eql(u8, op, "contains"))
            left.contains(right)
        else
            false;

        return Value.initBool(result);
    }

    fn compareLess(self: *Self, left: Value, right: Value) bool {
        _ = self;
        return switch (left) {
            .integer => |l| switch (right) {
                .integer => |r| l < r,
                .float => |r| @as(f64, @floatFromInt(l)) < r,
                else => false,
            },
            .float => |l| switch (right) {
                .float => |r| l < r,
                .integer => |r| l < @as(f64, @floatFromInt(r)),
                else => false,
            },
            .string => |l| switch (right) {
                .string => |r| std.mem.lessThan(u8, l, r),
                else => false,
            },
            else => false,
        };
    }

    fn compareGreater(self: *Self, left: Value, right: Value) bool {
        _ = self;
        return switch (left) {
            .integer => |l| switch (right) {
                .integer => |r| l > r,
                .float => |r| @as(f64, @floatFromInt(l)) > r,
                else => false,
            },
            .float => |l| switch (right) {
                .float => |r| l > r,
                .integer => |r| l > @as(f64, @floatFromInt(r)),
                else => false,
            },
            .string => |l| switch (right) {
                .string => |r| std.mem.order(u8, l, r) == .gt,
                else => false,
            },
            else => false,
        };
    }

    fn compareLessOrEqual(self: *Self, left: Value, right: Value) bool {
        return left.eql(right) or self.compareLess(left, right);
    }

    fn compareGreaterOrEqual(self: *Self, left: Value, right: Value) bool {
        return left.eql(right) or self.compareGreater(left, right);
    }

    fn evaluateLogical(self: *Self, node: Node) RenderError!Value {
        if (node.children.items.len < 2) return Value.initBool(false);

        const left = try self.evaluateNode(node.children.items[0]);
        const op = node.operator orelse "and";

        if (std.mem.eql(u8, op, "and")) {
            if (!left.isTruthy()) return Value.initBool(false);
            const right = try self.evaluateNode(node.children.items[1]);
            return Value.initBool(right.isTruthy());
        } else if (std.mem.eql(u8, op, "or")) {
            if (left.isTruthy()) return Value.initBool(true);
            const right = try self.evaluateNode(node.children.items[1]);
            return Value.initBool(right.isTruthy());
        }

        return Value.initBool(false);
    }

    fn applyFilter(self: *Self, value: Value, filter_node: Node) RenderError!Value {
        const name = filter_node.filter_name orelse return value;
        const args = if (filter_node.filter_args) |a| a.items else &[_]Node{};

        return self.executeFilter(name, value, args);
    }

    fn executeFilter(self: *Self, name: []const u8, value: Value, args: []const Node) RenderError!Value {
        // String filters
        if (std.mem.eql(u8, name, "upcase")) {
            return self.filterUpcase(value);
        } else if (std.mem.eql(u8, name, "downcase")) {
            return self.filterDowncase(value);
        } else if (std.mem.eql(u8, name, "capitalize")) {
            return self.filterCapitalize(value);
        } else if (std.mem.eql(u8, name, "strip")) {
            return self.filterStrip(value);
        } else if (std.mem.eql(u8, name, "lstrip")) {
            return self.filterLstrip(value);
        } else if (std.mem.eql(u8, name, "rstrip")) {
            return self.filterRstrip(value);
        } else if (std.mem.eql(u8, name, "strip_html")) {
            return self.filterStripHtml(value);
        } else if (std.mem.eql(u8, name, "strip_newlines")) {
            return self.filterStripNewlines(value);
        } else if (std.mem.eql(u8, name, "newline_to_br")) {
            return self.filterNewlineToBr(value);
        } else if (std.mem.eql(u8, name, "escape")) {
            return self.filterEscape(value);
        } else if (std.mem.eql(u8, name, "escape_once")) {
            return self.filterEscapeOnce(value);
        } else if (std.mem.eql(u8, name, "url_encode")) {
            return self.filterUrlEncode(value);
        } else if (std.mem.eql(u8, name, "url_decode")) {
            return self.filterUrlDecode(value);
        } else if (std.mem.eql(u8, name, "append")) {
            return self.filterAppend(value, args);
        } else if (std.mem.eql(u8, name, "prepend")) {
            return self.filterPrepend(value, args);
        } else if (std.mem.eql(u8, name, "remove")) {
            return self.filterRemove(value, args);
        } else if (std.mem.eql(u8, name, "remove_first")) {
            return self.filterRemoveFirst(value, args);
        } else if (std.mem.eql(u8, name, "remove_last")) {
            return self.filterRemoveLast(value, args);
        } else if (std.mem.eql(u8, name, "replace")) {
            return self.filterReplace(value, args);
        } else if (std.mem.eql(u8, name, "replace_first")) {
            return self.filterReplaceFirst(value, args);
        } else if (std.mem.eql(u8, name, "replace_last")) {
            return self.filterReplaceLast(value, args);
        } else if (std.mem.eql(u8, name, "split")) {
            return self.filterSplit(value, args);
        } else if (std.mem.eql(u8, name, "truncate")) {
            return self.filterTruncate(value, args);
        } else if (std.mem.eql(u8, name, "truncatewords")) {
            return self.filterTruncatewords(value, args);
        } else if (std.mem.eql(u8, name, "slice")) {
            return self.filterSlice(value, args);
        }
        // Array filters
        else if (std.mem.eql(u8, name, "size")) {
            return Value.initInt(value.size());
        } else if (std.mem.eql(u8, name, "first")) {
            return self.filterFirst(value);
        } else if (std.mem.eql(u8, name, "last")) {
            return self.filterLast(value);
        } else if (std.mem.eql(u8, name, "join")) {
            return self.filterJoin(value, args);
        } else if (std.mem.eql(u8, name, "reverse")) {
            return self.filterReverse(value);
        } else if (std.mem.eql(u8, name, "sort")) {
            return self.filterSort(value);
        } else if (std.mem.eql(u8, name, "sort_natural")) {
            return self.filterSortNatural(value);
        } else if (std.mem.eql(u8, name, "uniq")) {
            return self.filterUniq(value);
        } else if (std.mem.eql(u8, name, "compact")) {
            return self.filterCompact(value, args);
        } else if (std.mem.eql(u8, name, "concat")) {
            return self.filterConcat(value, args);
        } else if (std.mem.eql(u8, name, "map")) {
            return self.filterMap(value, args);
        } else if (std.mem.eql(u8, name, "where")) {
            return self.filterWhere(value, args);
        }
        // Additional array filters
        else if (std.mem.eql(u8, name, "find")) {
            return self.filterFind(value, args);
        } else if (std.mem.eql(u8, name, "find_index")) {
            return self.filterFindIndex(value, args);
        } else if (std.mem.eql(u8, name, "has")) {
            return self.filterHas(value, args);
        } else if (std.mem.eql(u8, name, "reject")) {
            return self.filterReject(value, args);
        } else if (std.mem.eql(u8, name, "sum")) {
            return self.filterSum(value);
        }
        // Math filters
        else if (std.mem.eql(u8, name, "plus")) {
            return self.filterPlus(value, args);
        } else if (std.mem.eql(u8, name, "minus")) {
            return self.filterMinus(value, args);
        } else if (std.mem.eql(u8, name, "times")) {
            return self.filterTimes(value, args);
        } else if (std.mem.eql(u8, name, "divided_by")) {
            return self.filterDividedBy(value, args);
        } else if (std.mem.eql(u8, name, "modulo")) {
            return self.filterModulo(value, args);
        } else if (std.mem.eql(u8, name, "abs")) {
            return self.filterAbs(value);
        } else if (std.mem.eql(u8, name, "ceil")) {
            return self.filterCeil(value);
        } else if (std.mem.eql(u8, name, "floor")) {
            return self.filterFloor(value);
        } else if (std.mem.eql(u8, name, "round")) {
            return self.filterRound(value, args);
        } else if (std.mem.eql(u8, name, "at_least")) {
            return self.filterAtLeast(value, args);
        } else if (std.mem.eql(u8, name, "at_most")) {
            return self.filterAtMost(value, args);
        }
        // Default filter
        else if (std.mem.eql(u8, name, "default")) {
            return self.filterDefault(value, args);
        }
        // Base64 filters
        else if (std.mem.eql(u8, name, "base64_encode")) {
            return self.filterBase64Encode(value);
        } else if (std.mem.eql(u8, name, "base64_decode")) {
            return self.filterBase64Decode(value);
        } else if (std.mem.eql(u8, name, "base64_url_safe_encode")) {
            return self.filterBase64UrlSafeEncode(value);
        } else if (std.mem.eql(u8, name, "base64_url_safe_decode")) {
            return self.filterBase64UrlSafeDecode(value);
        }
        // Hash and encoding filters
        else if (std.mem.eql(u8, name, "json")) {
            return self.filterJson(value);
        } else if (std.mem.eql(u8, name, "sha256")) {
            return self.filterSha256(value);
        } else if (std.mem.eql(u8, name, "md5")) {
            return self.filterMd5(value);
        } else if (std.mem.eql(u8, name, "date")) {
            return self.filterDate(value, args);
        }

        return value;
    }

    // String filters implementation
    fn filterUpcase(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        var result = self.workAllocator().alloc(u8, str.len) catch return RenderError.OutOfMemory;
        for (str, 0..) |c, i| {
            result[i] = std.ascii.toUpper(c);
        }
        return Value.initString(result);
    }

    fn filterDowncase(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        var result = self.workAllocator().alloc(u8, str.len) catch return RenderError.OutOfMemory;
        for (str, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return Value.initString(result);
    }

    fn filterCapitalize(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (str.len == 0) return Value.initString("");

        var result = self.workAllocator().alloc(u8, str.len) catch return RenderError.OutOfMemory;
        result[0] = std.ascii.toUpper(str[0]);
        for (str[1..], 1..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return Value.initString(result);
    }

    fn filterStrip(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        return Value.initString(std.mem.trim(u8, str, " \t\n\r"));
    }

    fn filterLstrip(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        return Value.initString(std.mem.trimLeft(u8, str, " \t\n\r"));
    }

    fn filterRstrip(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        return Value.initString(std.mem.trimRight(u8, str, " \t\n\r"));
    }

    fn filterStripHtml(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        var result: std.ArrayList(u8) = .empty;
        var in_tag = false;

        for (str) |c| {
            if (c == '<') {
                in_tag = true;
            } else if (c == '>') {
                in_tag = false;
            } else if (!in_tag) {
                result.append(self.workAllocator(), c) catch return RenderError.OutOfMemory;
            }
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterStripNewlines(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        var result: std.ArrayList(u8) = .empty;

        for (str) |c| {
            if (c != '\n' and c != '\r') {
                result.append(self.workAllocator(), c) catch return RenderError.OutOfMemory;
            }
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterNewlineToBr(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        var result: std.ArrayList(u8) = .empty;

        var i: usize = 0;
        while (i < str.len) : (i += 1) {
            if (str[i] == '\r' and i + 1 < str.len and str[i + 1] == '\n') {
                // \r\n is treated as single newline - skip the \r
                continue;
            } else if (str[i] == '\n') {
                result.appendSlice(self.workAllocator(), "<br />\n") catch return RenderError.OutOfMemory;
            } else {
                result.append(self.workAllocator(), str[i]) catch return RenderError.OutOfMemory;
            }
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterEscape(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        var result: std.ArrayList(u8) = .empty;

        for (str) |c| {
            switch (c) {
                '&' => result.appendSlice(self.workAllocator(), "&amp;") catch return RenderError.OutOfMemory,
                '<' => result.appendSlice(self.workAllocator(), "&lt;") catch return RenderError.OutOfMemory,
                '>' => result.appendSlice(self.workAllocator(), "&gt;") catch return RenderError.OutOfMemory,
                '"' => result.appendSlice(self.workAllocator(), "&quot;") catch return RenderError.OutOfMemory,
                '\'' => result.appendSlice(self.workAllocator(), "&#39;") catch return RenderError.OutOfMemory,
                else => result.append(self.workAllocator(), c) catch return RenderError.OutOfMemory,
            }
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterEscapeOnce(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        var result: std.ArrayList(u8) = .empty;

        var i: usize = 0;
        while (i < str.len) {
            const c = str[i];
            if (c == '&') {
                // Check if this is already an HTML entity
                // Look for pattern &...;
                var j = i + 1;
                var found_semi = false;
                while (j < str.len and j < i + 10) : (j += 1) {
                    if (str[j] == ';') {
                        found_semi = true;
                        break;
                    }
                    if (!std.ascii.isAlphanumeric(str[j]) and str[j] != '#') {
                        break;
                    }
                }

                if (found_semi and j > i + 1) {
                    // This looks like an HTML entity, copy it as-is
                    result.appendSlice(self.workAllocator(), str[i .. j + 1]) catch return RenderError.OutOfMemory;
                    i = j + 1;
                } else {
                    // Not an entity, escape the ampersand
                    result.appendSlice(self.workAllocator(), "&amp;") catch return RenderError.OutOfMemory;
                    i += 1;
                }
            } else {
                switch (c) {
                    '<' => result.appendSlice(self.workAllocator(), "&lt;") catch return RenderError.OutOfMemory,
                    '>' => result.appendSlice(self.workAllocator(), "&gt;") catch return RenderError.OutOfMemory,
                    '"' => result.appendSlice(self.workAllocator(), "&quot;") catch return RenderError.OutOfMemory,
                    '\'' => result.appendSlice(self.workAllocator(), "&#39;") catch return RenderError.OutOfMemory,
                    else => result.append(self.workAllocator(), c) catch return RenderError.OutOfMemory,
                }
                i += 1;
            }
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterUrlEncode(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        var result: std.ArrayList(u8) = .empty;

        for (str) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
                result.append(self.workAllocator(), c) catch return RenderError.OutOfMemory;
            } else if (c == ' ') {
                result.append(self.workAllocator(), '+') catch return RenderError.OutOfMemory;
            } else {
                result.append(self.workAllocator(), '%') catch return RenderError.OutOfMemory;
                const hex = "0123456789ABCDEF";
                result.append(self.workAllocator(), hex[c >> 4]) catch return RenderError.OutOfMemory;
                result.append(self.workAllocator(), hex[c & 0xF]) catch return RenderError.OutOfMemory;
            }
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterUrlDecode(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        var result: std.ArrayList(u8) = .empty;
        var i: usize = 0;

        while (i < str.len) {
            if (str[i] == '%' and i + 2 < str.len) {
                const hex = str[i + 1 .. i + 3];
                const byte = std.fmt.parseInt(u8, hex, 16) catch {
                    result.append(self.workAllocator(), str[i]) catch return RenderError.OutOfMemory;
                    i += 1;
                    continue;
                };
                result.append(self.workAllocator(), byte) catch return RenderError.OutOfMemory;
                i += 3;
            } else if (str[i] == '+') {
                result.append(self.workAllocator(), ' ') catch return RenderError.OutOfMemory;
                i += 1;
            } else {
                result.append(self.workAllocator(), str[i]) catch return RenderError.OutOfMemory;
                i += 1;
            }
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterAppend(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (args.len == 0) return value;

        const suffix = try self.evaluateNode(args[0]);
        const suffix_str = suffix.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        var result: std.ArrayList(u8) = .empty;
        result.appendSlice(self.workAllocator(), str) catch return RenderError.OutOfMemory;
        result.appendSlice(self.workAllocator(), suffix_str) catch return RenderError.OutOfMemory;

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterPrepend(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (args.len == 0) return value;

        const prefix = try self.evaluateNode(args[0]);
        const prefix_str = prefix.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        var result: std.ArrayList(u8) = .empty;
        result.appendSlice(self.workAllocator(), prefix_str) catch return RenderError.OutOfMemory;
        result.appendSlice(self.workAllocator(), str) catch return RenderError.OutOfMemory;

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterRemove(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (args.len == 0) return value;

        const needle = try self.evaluateNode(args[0]);
        const needle_str = needle.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        // Empty needle or nil returns original
        if (needle_str.len == 0 or needle == .nil) return value;

        var result: std.ArrayList(u8) = .empty;
        var i: usize = 0;
        while (i < str.len) {
            if (i + needle_str.len <= str.len and std.mem.eql(u8, str[i .. i + needle_str.len], needle_str)) {
                i += needle_str.len;
            } else {
                result.append(self.workAllocator(), str[i]) catch return RenderError.OutOfMemory;
                i += 1;
            }
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterRemoveFirst(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (args.len == 0) return value;

        const needle = try self.evaluateNode(args[0]);
        const needle_str = needle.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        // Empty needle or nil returns original
        if (needle_str.len == 0 or needle == .nil) return value;

        if (std.mem.indexOf(u8, str, needle_str)) |idx| {
            var result: std.ArrayList(u8) = .empty;
            result.appendSlice(self.workAllocator(), str[0..idx]) catch return RenderError.OutOfMemory;
            result.appendSlice(self.workAllocator(), str[idx + needle_str.len ..]) catch return RenderError.OutOfMemory;
            return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
        }

        return value;
    }

    fn filterRemoveLast(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (args.len == 0) return value;

        const needle = try self.evaluateNode(args[0]);
        const needle_str = needle.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        // Empty needle or nil returns original
        if (needle_str.len == 0 or needle == .nil) return value;

        if (std.mem.lastIndexOf(u8, str, needle_str)) |idx| {
            var result: std.ArrayList(u8) = .empty;
            result.appendSlice(self.workAllocator(), str[0..idx]) catch return RenderError.OutOfMemory;
            result.appendSlice(self.workAllocator(), str[idx + needle_str.len ..]) catch return RenderError.OutOfMemory;
            return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
        }

        return value;
    }

    fn filterReplace(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (args.len < 1) return value;

        const needle = try self.evaluateNode(args[0]);
        const needle_str = needle.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        // Second argument defaults to empty string
        const replacement_str: []const u8 = if (args.len > 1) blk: {
            const replacement = try self.evaluateNode(args[1]);
            break :blk replacement.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        } else "";

        // Empty needle or nil: insert replacement between each character
        if (needle_str.len == 0 or needle == .nil) {
            var result: std.ArrayList(u8) = .empty;
            result.appendSlice(self.workAllocator(), replacement_str) catch return RenderError.OutOfMemory;
            for (str) |c| {
                result.append(self.workAllocator(), c) catch return RenderError.OutOfMemory;
                result.appendSlice(self.workAllocator(), replacement_str) catch return RenderError.OutOfMemory;
            }
            return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
        }

        var result: std.ArrayList(u8) = .empty;
        var i: usize = 0;
        while (i < str.len) {
            if (i + needle_str.len <= str.len and std.mem.eql(u8, str[i .. i + needle_str.len], needle_str)) {
                result.appendSlice(self.workAllocator(), replacement_str) catch return RenderError.OutOfMemory;
                i += needle_str.len;
            } else {
                result.append(self.workAllocator(), str[i]) catch return RenderError.OutOfMemory;
                i += 1;
            }
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterReplaceFirst(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (args.len < 1) return value;

        const needle = try self.evaluateNode(args[0]);
        const needle_str = needle.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        // Second argument defaults to empty string
        const replacement_str: []const u8 = if (args.len > 1) blk: {
            const replacement = try self.evaluateNode(args[1]);
            break :blk replacement.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        } else "";

        // Empty needle or nil: prepend replacement
        if (needle_str.len == 0 or needle == .nil) {
            var result: std.ArrayList(u8) = .empty;
            result.appendSlice(self.workAllocator(), replacement_str) catch return RenderError.OutOfMemory;
            result.appendSlice(self.workAllocator(), str) catch return RenderError.OutOfMemory;
            return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
        }

        if (std.mem.indexOf(u8, str, needle_str)) |idx| {
            var result: std.ArrayList(u8) = .empty;
            result.appendSlice(self.workAllocator(), str[0..idx]) catch return RenderError.OutOfMemory;
            result.appendSlice(self.workAllocator(), replacement_str) catch return RenderError.OutOfMemory;
            result.appendSlice(self.workAllocator(), str[idx + needle_str.len ..]) catch return RenderError.OutOfMemory;
            return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
        }

        return value;
    }

    fn filterReplaceLast(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (args.len < 1) return value;

        const needle = try self.evaluateNode(args[0]);
        const needle_str = needle.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        // Second argument defaults to empty string
        const replacement_str: []const u8 = if (args.len > 1) blk: {
            const replacement = try self.evaluateNode(args[1]);
            break :blk replacement.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        } else "";

        // Empty needle or nil: append replacement
        if (needle_str.len == 0 or needle == .nil) {
            var result: std.ArrayList(u8) = .empty;
            result.appendSlice(self.workAllocator(), str) catch return RenderError.OutOfMemory;
            result.appendSlice(self.workAllocator(), replacement_str) catch return RenderError.OutOfMemory;
            return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
        }

        if (std.mem.lastIndexOf(u8, str, needle_str)) |idx| {
            var result: std.ArrayList(u8) = .empty;
            result.appendSlice(self.workAllocator(), str[0..idx]) catch return RenderError.OutOfMemory;
            result.appendSlice(self.workAllocator(), replacement_str) catch return RenderError.OutOfMemory;
            result.appendSlice(self.workAllocator(), str[idx + needle_str.len ..]) catch return RenderError.OutOfMemory;
            return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
        }

        return value;
    }

    fn filterSplit(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        const delimiter = if (args.len > 0) blk: {
            const d = try self.evaluateNode(args[0]);
            break :blk d.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        } else " ";

        var result: std.ArrayList(Value) = .empty;
        var iter = std.mem.splitSequence(u8, str, delimiter);
        while (iter.next()) |part| {
            result.append(self.workAllocator(), Value.initString(part)) catch return RenderError.OutOfMemory;
        }

        return Value.initArray(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterTruncate(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        const length: usize = if (args.len > 0) blk: {
            const l = try self.evaluateNode(args[0]);
            break :blk @intCast(switch (l) {
                .integer => |i| if (i > 0) i else 50,
                else => 50,
            });
        } else 50;

        const ellipsis = if (args.len > 1) blk: {
            const e = try self.evaluateNode(args[1]);
            break :blk e.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        } else "...";

        if (str.len <= length) return value;

        const cut_at = if (length > ellipsis.len) length - ellipsis.len else 0;
        var result: std.ArrayList(u8) = .empty;
        result.appendSlice(self.workAllocator(), str[0..cut_at]) catch return RenderError.OutOfMemory;
        result.appendSlice(self.workAllocator(), ellipsis) catch return RenderError.OutOfMemory;

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterTruncatewords(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        const word_count: usize = if (args.len > 0) blk: {
            const w = try self.evaluateNode(args[0]);
            break :blk @intCast(switch (w) {
                .integer => |i| if (i > 0) i else 15,
                else => 15,
            });
        } else 15;

        const ellipsis = if (args.len > 1) blk: {
            const e = try self.evaluateNode(args[1]);
            break :blk e.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        } else "...";

        var result: std.ArrayList(u8) = .empty;
        var words: usize = 0;
        var in_word = false;

        for (str, 0..) |c, i| {
            if (std.ascii.isWhitespace(c)) {
                if (in_word) {
                    words += 1;
                    if (words >= word_count) {
                        result.appendSlice(self.workAllocator(), ellipsis) catch return RenderError.OutOfMemory;
                        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
                    }
                    in_word = false;
                }
                result.append(self.workAllocator(), c) catch return RenderError.OutOfMemory;
            } else {
                in_word = true;
                result.append(self.workAllocator(), c) catch return RenderError.OutOfMemory;
            }
            _ = i;
        }

        return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterSlice(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;

        const start_arg = try self.evaluateNode(args[0]);
        var start: i64 = switch (start_arg) {
            .integer => |i| i,
            else => 0,
        };

        switch (value) {
            .string => |str| {
                const len = @as(i64, @intCast(str.len));
                if (start < 0) start = len + start;
                if (start < 0) start = 0;
                if (start >= len) return Value.initString("");

                const ustart: usize = @intCast(start);
                const length: usize = if (args.len > 1) blk: {
                    const l = try self.evaluateNode(args[1]);
                    break :blk @intCast(switch (l) {
                        .integer => |i| if (i > 0) i else 1,
                        else => 1,
                    });
                } else 1;

                const end = @min(ustart + length, str.len);
                return Value.initString(str[ustart..end]);
            },
            .array => |arr| {
                const len = @as(i64, @intCast(arr.len));
                if (start < 0) start = len + start;
                if (start < 0) start = 0;
                if (start >= len) return Value.initArray(&[_]Value{});

                const ustart: usize = @intCast(start);
                const length: usize = if (args.len > 1) blk: {
                    const l = try self.evaluateNode(args[1]);
                    break :blk @intCast(switch (l) {
                        .integer => |i| if (i > 0) i else 1,
                        else => 1,
                    });
                } else 1;

                const end = @min(ustart + length, arr.len);
                return Value.initArray(arr[ustart..end]);
            },
            else => return value,
        }
    }

    // Array filters
    fn filterFirst(self: *Self, value: Value) RenderError!Value {
        return switch (value) {
            .array => |arr| if (arr.len > 0) arr[0] else Value.initNil(),
            .string => |str| if (str.len > 0) Value.initString(str[0..1]) else Value.initNil(),
            .object => |obj| {
                // Return first key-value pair as [key, value] array
                var it = obj.map.iterator();
                if (it.next()) |entry| {
                    var pair = self.workAllocator().alloc(Value, 2) catch return RenderError.OutOfMemory;
                    pair[0] = Value.initString(entry.key_ptr.*);
                    pair[1] = entry.value_ptr.*;
                    return Value.initArray(pair);
                }
                return Value.initNil();
            },
            else => Value.initNil(),
        };
    }

    fn filterLast(self: *Self, value: Value) RenderError!Value {
        _ = self;
        return switch (value) {
            .array => |arr| if (arr.len > 0) arr[arr.len - 1] else Value.initNil(),
            .string => |str| if (str.len > 0) Value.initString(str[str.len - 1 ..]) else Value.initNil(),
            // Hash returns nil (unlike first which returns first key-value pair)
            else => Value.initNil(),
        };
    }

    fn filterJoin(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const delimiter = if (args.len > 0) blk: {
            const d = try self.evaluateNode(args[0]);
            break :blk d.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        } else " ";

        switch (value) {
            .array => |arr| {
                var result: std.ArrayList(u8) = .empty;
                for (arr, 0..) |item, i| {
                    if (i > 0) result.appendSlice(self.workAllocator(), delimiter) catch return RenderError.OutOfMemory;
                    const s = item.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
                    result.appendSlice(self.workAllocator(), s) catch return RenderError.OutOfMemory;
                }
                return Value.initString(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
            },
            else => return value,
        }
    }

    fn filterReverse(self: *Self, value: Value) RenderError!Value {
        switch (value) {
            .array => |arr| {
                var result = self.workAllocator().alloc(Value, arr.len) catch return RenderError.OutOfMemory;
                for (arr, 0..) |item, i| {
                    result[arr.len - 1 - i] = item;
                }
                return Value.initArray(result);
            },
            .string => |str| {
                var result = self.workAllocator().alloc(u8, str.len) catch return RenderError.OutOfMemory;
                for (str, 0..) |c, i| {
                    result[str.len - 1 - i] = c;
                }
                return Value.initString(result);
            },
            else => return value,
        }
    }

    fn filterSort(self: *Self, value: Value) RenderError!Value {
        _ = self;
        // Simple implementation - just return as is for now
        return value;
    }

    fn filterSortNatural(self: *Self, value: Value) RenderError!Value {
        _ = self;
        return value;
    }

    fn filterUniq(self: *Self, value: Value) RenderError!Value {
        switch (value) {
            .array => |arr| {
                var result: std.ArrayList(Value) = .empty;
                for (arr) |item| {
                    var found = false;
                    for (result.items) |existing| {
                        if (item.eql(existing)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                    }
                }
                return Value.initArray(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
            },
            else => return value,
        }
    }

    fn filterCompact(self: *Self, value: Value, args: []const Node) RenderError!Value {
        // Get optional key argument
        const key: ?[]const u8 = if (args.len > 0) blk: {
            const key_val = try self.evaluateNode(args[0]);
            break :blk switch (key_val) {
                .string => |s| s,
                else => null,
            };
        } else null;

        switch (value) {
            .array => |arr| {
                var result: std.ArrayList(Value) = .empty;
                for (arr) |item| {
                    if (key) |k| {
                        // Filter by key - keep objects where key's value is not nil
                        if (item == .object) {
                            if (item.object.get(k)) |val| {
                                if (val != .nil) {
                                    result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                                }
                            }
                        }
                    } else {
                        // No key - filter out nil items
                        if (item != .nil) {
                            result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                        }
                    }
                }
                return Value.initArray(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
            },
            .nil => return Value.initArray(&[_]Value{}),
            else => {
                // Non-array values become single-element arrays
                var result: std.ArrayList(Value) = .empty;
                result.append(self.workAllocator(), value) catch return RenderError.OutOfMemory;
                return Value.initArray(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
            },
        }
    }

    fn filterConcat(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;

        const other = try self.evaluateNode(args[0]);

        // Build result array
        var result: std.ArrayList(Value) = .empty;

        // Add items from left value
        switch (value) {
            .array => |arr| {
                for (arr) |item| {
                    // Flatten nested arrays
                    if (item == .array) {
                        for (item.array) |sub_item| {
                            result.append(self.workAllocator(), sub_item) catch return RenderError.OutOfMemory;
                        }
                    } else {
                        result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                    }
                }
            },
            .nil => {}, // nil becomes empty array
            else => {
                // Non-array values become single-element arrays
                result.append(self.workAllocator(), value) catch return RenderError.OutOfMemory;
            },
        }

        // Add items from argument
        switch (other) {
            .array => |other_arr| {
                for (other_arr) |item| {
                    result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                }
            },
            .nil => {}, // nil becomes empty array
            else => {
                result.append(self.workAllocator(), other) catch return RenderError.OutOfMemory;
            },
        }

        return Value.initArray(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
    }

    fn filterMap(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;

        const prop = try self.evaluateNode(args[0]);

        // If property is nil or undefined, return empty array
        if (prop == .nil) {
            return Value.initArray(&[_]Value{});
        }

        const prop_str: []const u8 = switch (prop) {
            .string => |s| s,
            else => return Value.initArray(&[_]Value{}),
        };

        switch (value) {
            .array => |arr| {
                var result: std.ArrayList(Value) = .empty;
                try self.mapArrayRecursive(arr, prop_str, &result);
                return Value.initArray(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
            },
            .object => |obj| {
                // For hash input, extract the property value directly
                if (obj.get(prop_str)) |val| {
                    var result = self.workAllocator().alloc(Value, 1) catch return RenderError.OutOfMemory;
                    result[0] = val;
                    return Value.initArray(result);
                }
                return Value.initArray(&[_]Value{});
            },
            else => return value,
        }
    }

    fn mapArrayRecursive(self: *Self, arr: []const Value, prop_str: []const u8, result: *std.ArrayList(Value)) RenderError!void {
        for (arr) |item| {
            switch (item) {
                .array => |nested| {
                    // Flatten nested arrays
                    try self.mapArrayRecursive(nested, prop_str, result);
                },
                .object => {
                    const mapped = item.get(prop_str) orelse Value.initNil();
                    result.append(self.workAllocator(), mapped) catch return RenderError.OutOfMemory;
                },
                else => {
                    const mapped = item.get(prop_str) orelse Value.initNil();
                    result.append(self.workAllocator(), mapped) catch return RenderError.OutOfMemory;
                },
            }
        }
    }

    fn filterWhere(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;

        const prop = try self.evaluateNode(args[0]);
        const prop_str = prop.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        const expected = if (args.len > 1) try self.evaluateNode(args[1]) else Value.initBool(true);

        switch (value) {
            .array => |arr| {
                var result: std.ArrayList(Value) = .empty;
                for (arr) |item| {
                    const val = item.get(prop_str) orelse Value.initNil();
                    if (val.eql(expected) or (args.len == 1 and val.isTruthy())) {
                        result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                    }
                }
                return Value.initArray(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
            },
            else => return value,
        }
    }

    // Math filters - helper to check if value should produce integer result
    fn isIntegerType(val: Value) bool {
        return switch (val) {
            .integer => true,
            .float => false,
            .nil => true, // nil converts to 0 (integer)
            .string => |s| {
                // Empty strings, non-numeric strings, and integer strings should result in integer
                if (s.len == 0) return true;
                // Check if string represents a float (has decimal point)
                if (std.mem.indexOfScalar(u8, s, '.') != null) return false;
                // Non-numeric strings also result in integer (0)
                _ = std.fmt.parseInt(i64, s, 10) catch return true;
                return true;
            },
            else => true, // Objects etc. convert to 0 (integer)
        };
    }

    // Helper to check if a value is explicitly a float type
    fn isFloatType(val: Value) bool {
        return switch (val) {
            .float => true,
            .string => |s| {
                if (std.mem.indexOfScalar(u8, s, '.') != null) {
                    _ = std.fmt.parseFloat(f64, s) catch return false;
                    return true;
                }
                return false;
            },
            else => false,
        };
    }

    fn filterPlus(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;
        const other = try self.evaluateNode(args[0]);

        const a = self.toNumber(value);
        const b = self.toNumber(other);
        const result = a + b;

        if (isIntegerType(value) and isIntegerType(other) and std.math.floor(result) == result) {
            return Value.initInt(@intFromFloat(result));
        }
        return Value.initFloat(result);
    }

    fn filterMinus(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;
        const other = try self.evaluateNode(args[0]);

        const a = self.toNumber(value);
        const b = self.toNumber(other);
        const result = a - b;

        if (isIntegerType(value) and isIntegerType(other) and std.math.floor(result) == result) {
            return Value.initInt(@intFromFloat(result));
        }
        return Value.initFloat(result);
    }

    fn filterTimes(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;
        const other = try self.evaluateNode(args[0]);

        const a = self.toNumber(value);
        const b = self.toNumber(other);
        const result = a * b;

        if (isIntegerType(value) and isIntegerType(other) and std.math.floor(result) == result) {
            return Value.initInt(@intFromFloat(result));
        }
        return Value.initFloat(result);
    }

    fn filterDividedBy(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;
        const other = try self.evaluateNode(args[0]);

        const a = self.toNumber(value);
        const b = self.toNumber(other);

        if (b == 0) return Value.initInt(0);

        // Integer division when both operands are integers
        if (isIntegerType(value) and isIntegerType(other)) {
            const result = @divTrunc(@as(i64, @intFromFloat(a)), @as(i64, @intFromFloat(b)));
            return Value.initInt(result);
        }
        return Value.initFloat(a / b);
    }

    fn filterModulo(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;
        const other = try self.evaluateNode(args[0]);

        const a = self.toNumber(value);
        const b = self.toNumber(other);

        if (b == 0) return Value.initInt(0);

        const result = @mod(a, b);
        if (isIntegerType(value) and isIntegerType(other) and std.math.floor(result) == result) {
            return Value.initInt(@intFromFloat(result));
        }
        return Value.initFloat(result);
    }

    fn filterAbs(self: *Self, value: Value) RenderError!Value {
        _ = self;
        return switch (value) {
            .integer => |i| Value.initInt(if (i < 0) -i else i),
            .float => |f| Value.initFloat(@abs(f)),
            .string => |s| blk: {
                // Try parsing as integer first
                if (std.fmt.parseInt(i64, s, 10)) |i| {
                    break :blk Value.initInt(if (i < 0) -i else i);
                } else |_| {}
                // Try parsing as float
                if (std.fmt.parseFloat(f64, s)) |f| {
                    break :blk Value.initFloat(@abs(f));
                } else |_| {}
                // Not a number, return 0
                break :blk Value.initInt(0);
            },
            .nil => Value.initInt(0),
            else => Value.initInt(0),
        };
    }

    fn filterCeil(_: *Self, value: Value) RenderError!Value {
        return switch (value) {
            .float => |f| Value.initInt(@intFromFloat(@ceil(f))),
            .integer => value,
            .string => |s| {
                if (std.fmt.parseFloat(f64, s)) |f| {
                    return Value.initInt(@intFromFloat(@ceil(f)));
                } else |_| {
                    return Value.initInt(0);
                }
            },
            .nil => Value.initInt(0),
            else => Value.initInt(0),
        };
    }

    fn filterFloor(_: *Self, value: Value) RenderError!Value {
        return switch (value) {
            .float => |f| Value.initInt(@intFromFloat(@floor(f))),
            .integer => value,
            .string => |s| {
                if (std.fmt.parseFloat(f64, s)) |f| {
                    return Value.initInt(@intFromFloat(@floor(f)));
                } else |_| {
                    return Value.initInt(0);
                }
            },
            .nil => Value.initInt(0),
            else => Value.initInt(0),
        };
    }

    fn filterRound(self: *Self, value: Value, args: []const Node) RenderError!Value {
        const precision: i32 = if (args.len > 0) blk: {
            const p = try self.evaluateNode(args[0]);
            break :blk switch (p) {
                .integer => |i| @intCast(i),
                .float => |f| @intFromFloat(f),
                .string => |s| std.fmt.parseInt(i32, s, 10) catch 0,
                else => 0,
            };
        } else 0;

        // nil/undefined returns 0 as integer
        if (value == .nil) {
            return Value.initInt(0);
        }

        const num: f64 = switch (value) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            .string => |s| std.fmt.parseFloat(f64, s) catch 0,
            else => 0,
        };

        // Precision <= 0 returns integer
        if (precision <= 0) {
            if (precision < 0) {
                const mult = std.math.pow(f64, 10.0, @floatFromInt(-precision));
                return Value.initInt(@intFromFloat(@round(num / mult) * mult));
            }
            return Value.initInt(@intFromFloat(@round(num)));
        } else {
            const mult = std.math.pow(f64, 10.0, @floatFromInt(precision));
            return Value.initFloat(@round(num * mult) / mult);
        }
    }

    fn filterAtLeast(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;
        const min = try self.evaluateNode(args[0]);

        // Get numeric values, treating nil/non-numeric as 0
        const val_num = self.toNumber(value);
        const min_num = self.toNumber(min);

        // nil value should use the min (positive) or 0 (negative)
        if (value == .nil) {
            if (min_num < 0) return Value.initInt(0);
            return switch (min) {
                .integer => |i| Value.initInt(i),
                .float => |f| Value.initFloat(f),
                else => Value.initInt(@intFromFloat(min_num)),
            };
        }

        // If value is a non-numeric string, use max(0, min)
        if (value == .string) {
            const str = value.string;
            if (std.fmt.parseFloat(f64, str)) |_| {
                // It's a numeric string - if value >= min, return original string
                if (val_num >= min_num) {
                    return value; // Return original string unchanged
                }
            } else |_| {
                // Non-numeric string - return max(0, min)
                if (min_num <= 0) return Value.initInt(0);
                return switch (min) {
                    .integer => |i| Value.initInt(i),
                    .float => |f| Value.initFloat(f),
                    else => Value.initInt(@intFromFloat(min_num)),
                };
            }
        }

        const result = @max(val_num, min_num);

        // Return integer if both inputs are integers, or if value is integer and arg is nil
        if ((value == .integer and min == .integer) or (value == .integer and min == .nil)) {
            return Value.initInt(@intFromFloat(result));
        }
        // If value is integer and result is a whole number, return integer
        if (value == .integer and std.math.floor(result) == result) {
            return Value.initInt(@intFromFloat(result));
        }
        // If min is integer and result equals min, return integer
        if (min == .integer and result == min_num) {
            return Value.initInt(@intFromFloat(result));
        }
        return Value.initFloat(result);
    }

    fn filterAtMost(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;
        const max = try self.evaluateNode(args[0]);

        // Get numeric values, treating nil/non-numeric as 0
        const val_num = self.toNumber(value);
        const max_num = self.toNumber(max);

        // If value is a string
        if (value == .string) {
            const str = value.string;
            if (std.fmt.parseFloat(f64, str)) |_| {
                // It's a numeric string - if value <= max, return original string
                if (val_num <= max_num) {
                    return value; // Return original string unchanged
                }
            } else |_| {
                // String is not a number, return min(0, max)
                const result = @min(@as(f64, 0), max_num);
                if (max == .integer) {
                    return Value.initInt(@intFromFloat(result));
                }
                return Value.initFloat(result);
            }
        }

        // nil value should use 0
        if (value == .nil) {
            const result = @min(@as(f64, 0), max_num);
            if (max == .integer) {
                return Value.initInt(@intFromFloat(result));
            }
            return Value.initFloat(result);
        }

        // Undefined argument should use 0
        if (max == .nil) {
            const result = @min(val_num, @as(f64, 0));
            if (value == .integer) {
                return Value.initInt(@intFromFloat(result));
            }
            return Value.initFloat(result);
        }

        const result = @min(val_num, max_num);

        // Return same type as input if both are integers
        if (value == .integer and max == .integer) {
            return Value.initInt(@intFromFloat(result));
        }
        // If max is integer and result equals max (i.e., max was the limiting factor), return integer
        if (max == .integer and result == max_num) {
            return Value.initInt(@intFromFloat(result));
        }
        return Value.initFloat(result);
    }

    fn toNumber(self: *Self, value: Value) f64 {
        _ = self;
        return switch (value) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            .string => |s| std.fmt.parseFloat(f64, s) catch 0,
            else => 0,
        };
    }

    fn filterDefault(self: *Self, value: Value, args: []const Node) RenderError!Value {
        // Check for allow_false option - can be first or second argument
        var allow_false = false;
        var default_arg_idx: ?usize = null;

        for (args, 0..) |arg, idx| {
            if (arg.value != null and std.mem.eql(u8, arg.value.?, "allow_false")) {
                if (arg.children.items.len > 0) {
                    const af_val = try self.evaluateNode(arg.children.items[0]);
                    allow_false = af_val.isTruthy();
                }
            } else if (default_arg_idx == null) {
                default_arg_idx = idx;
            }
        }

        if (value.isTruthy()) {
            return value;
        }

        if (allow_false) {
            switch (value) {
                .boolean => |b| if (!b) return value, // false is allowed
                else => {},
            }
        }

        // If no default argument provided, use empty string
        if (default_arg_idx) |idx| {
            return try self.evaluateNode(args[idx]);
        } else {
            return Value.initString("");
        }
    }

    // Base64 filters
    fn filterBase64Encode(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (str.len == 0) return Value.initString("");

        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        const encoded_len = ((str.len + 2) / 3) * 4;
        var result = self.workAllocator().alloc(u8, encoded_len) catch return RenderError.OutOfMemory;

        var i: usize = 0;
        var j: usize = 0;
        while (i < str.len) {
            const b0: u32 = str[i];
            const b1: u32 = if (i + 1 < str.len) str[i + 1] else 0;
            const b2: u32 = if (i + 2 < str.len) str[i + 2] else 0;

            const triple = (b0 << 16) | (b1 << 8) | b2;

            result[j] = alphabet[(triple >> 18) & 0x3F];
            result[j + 1] = alphabet[(triple >> 12) & 0x3F];
            result[j + 2] = if (i + 1 < str.len) alphabet[(triple >> 6) & 0x3F] else '=';
            result[j + 3] = if (i + 2 < str.len) alphabet[triple & 0x3F] else '=';

            i += 3;
            j += 4;
        }

        return Value.initString(result);
    }

    fn filterBase64Decode(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (str.len == 0) return Value.initString("");

        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        // Count padding
        var padding: usize = 0;
        if (str.len > 0 and str[str.len - 1] == '=') padding += 1;
        if (str.len > 1 and str[str.len - 2] == '=') padding += 1;

        const decoded_len = (str.len / 4) * 3 - padding;
        var result = self.workAllocator().alloc(u8, decoded_len) catch return RenderError.OutOfMemory;

        var i: usize = 0;
        var j: usize = 0;
        while (i < str.len) {
            const indexOf = struct {
                fn f(c: u8, alpha: []const u8) u32 {
                    for (alpha, 0..) |a, idx| {
                        if (a == c) return @intCast(idx);
                    }
                    return 0;
                }
            }.f;

            const c0 = indexOf(str[i], alphabet);
            const c1 = if (i + 1 < str.len) indexOf(str[i + 1], alphabet) else 0;
            const c2 = if (i + 2 < str.len and str[i + 2] != '=') indexOf(str[i + 2], alphabet) else 0;
            const c3 = if (i + 3 < str.len and str[i + 3] != '=') indexOf(str[i + 3], alphabet) else 0;

            const triple = (c0 << 18) | (c1 << 12) | (c2 << 6) | c3;

            if (j < decoded_len) result[j] = @intCast((triple >> 16) & 0xFF);
            if (j + 1 < decoded_len) result[j + 1] = @intCast((triple >> 8) & 0xFF);
            if (j + 2 < decoded_len) result[j + 2] = @intCast(triple & 0xFF);

            i += 4;
            j += 3;
        }

        return Value.initString(result);
    }

    fn filterBase64UrlSafeEncode(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (str.len == 0) return Value.initString("");

        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        const encoded_len = ((str.len + 2) / 3) * 4;
        var result = self.workAllocator().alloc(u8, encoded_len) catch return RenderError.OutOfMemory;

        var i: usize = 0;
        var j: usize = 0;
        while (i < str.len) {
            const b0: u32 = str[i];
            const b1: u32 = if (i + 1 < str.len) str[i + 1] else 0;
            const b2: u32 = if (i + 2 < str.len) str[i + 2] else 0;

            const triple = (b0 << 16) | (b1 << 8) | b2;

            result[j] = alphabet[(triple >> 18) & 0x3F];
            result[j + 1] = alphabet[(triple >> 12) & 0x3F];
            result[j + 2] = if (i + 1 < str.len) alphabet[(triple >> 6) & 0x3F] else '=';
            result[j + 3] = if (i + 2 < str.len) alphabet[triple & 0x3F] else '=';

            i += 3;
            j += 4;
        }

        return Value.initString(result);
    }

    fn filterBase64UrlSafeDecode(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (str.len == 0) return Value.initString("");

        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

        // Count padding
        var padding: usize = 0;
        if (str.len > 0 and str[str.len - 1] == '=') padding += 1;
        if (str.len > 1 and str[str.len - 2] == '=') padding += 1;

        const decoded_len = (str.len / 4) * 3 - padding;
        var result = self.workAllocator().alloc(u8, decoded_len) catch return RenderError.OutOfMemory;

        var i: usize = 0;
        var j: usize = 0;
        while (i < str.len) {
            const indexOf = struct {
                fn f(c: u8, alpha: []const u8) u32 {
                    for (alpha, 0..) |a, idx| {
                        if (a == c) return @intCast(idx);
                    }
                    return 0;
                }
            }.f;

            const c0 = indexOf(str[i], alphabet);
            const c1 = if (i + 1 < str.len) indexOf(str[i + 1], alphabet) else 0;
            const c2 = if (i + 2 < str.len and str[i + 2] != '=') indexOf(str[i + 2], alphabet) else 0;
            const c3 = if (i + 3 < str.len and str[i + 3] != '=') indexOf(str[i + 3], alphabet) else 0;

            const triple = (c0 << 18) | (c1 << 12) | (c2 << 6) | c3;

            if (j < decoded_len) result[j] = @intCast((triple >> 16) & 0xFF);
            if (j + 1 < decoded_len) result[j + 1] = @intCast((triple >> 8) & 0xFF);
            if (j + 2 < decoded_len) result[j + 2] = @intCast(triple & 0xFF);

            i += 4;
            j += 3;
        }

        return Value.initString(result);
    }

    // Hash and encoding filter implementations
    fn filterJson(self: *Self, value: Value) RenderError!Value {
        const allocator = self.workAllocator();

        // Convert value to JSON string
        const json_str = switch (value) {
            .nil => "null",
            .boolean => |b| if (b) "true" else "false",
            .integer => |i| std.fmt.allocPrint(allocator, "{d}", .{i}) catch return RenderError.OutOfMemory,
            .float => |f| std.fmt.allocPrint(allocator, "{d}", .{f}) catch return RenderError.OutOfMemory,
            .string => |s| blk: {
                var result: std.ArrayList(u8) = .empty;
                result.appendSlice(allocator, "\"") catch return RenderError.OutOfMemory;

                for (s) |c| {
                    switch (c) {
                        '\\' => result.appendSlice(allocator, "\\\\") catch return RenderError.OutOfMemory,
                        '"' => result.appendSlice(allocator, "\\\"") catch return RenderError.OutOfMemory,
                        '\n' => result.appendSlice(allocator, "\\n") catch return RenderError.OutOfMemory,
                        '\r' => result.appendSlice(allocator, "\\r") catch return RenderError.OutOfMemory,
                        '\t' => result.appendSlice(allocator, "\\t") catch return RenderError.OutOfMemory,
                        else => result.append(allocator, c) catch return RenderError.OutOfMemory,
                    }
                }

                result.appendSlice(allocator, "\"") catch return RenderError.OutOfMemory;
                break :blk result.toOwnedSlice(allocator) catch return RenderError.OutOfMemory;
            },
            .array => |arr| blk: {
                var result: std.ArrayList(u8) = .empty;
                result.append(allocator, '[') catch return RenderError.OutOfMemory;

                for (arr, 0..) |item, i| {
                    if (i > 0) {
                        result.appendSlice(allocator, ",") catch return RenderError.OutOfMemory;
                    }
                    const item_json = try self.filterJson(item);
                    const item_str = item_json.toString(allocator) catch return RenderError.OutOfMemory;
                    result.appendSlice(allocator, item_str) catch return RenderError.OutOfMemory;
                }

                result.append(allocator, ']') catch return RenderError.OutOfMemory;
                break :blk result.toOwnedSlice(allocator) catch return RenderError.OutOfMemory;
            },
            .object => |obj| blk: {
                var result: std.ArrayList(u8) = .empty;
                result.append(allocator, '{') catch return RenderError.OutOfMemory;

                var it = obj.map.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) {
                        result.appendSlice(allocator, ",") catch return RenderError.OutOfMemory;
                    }
                    first = false;

                    // Key (with escaping)
                    result.appendSlice(allocator, "\"") catch return RenderError.OutOfMemory;
                    result.appendSlice(allocator, entry.key_ptr.*) catch return RenderError.OutOfMemory;
                    result.appendSlice(allocator, "\":") catch return RenderError.OutOfMemory;

                    // Value
                    const value_json = try self.filterJson(entry.value_ptr.*);
                    const value_str = value_json.toString(allocator) catch return RenderError.OutOfMemory;
                    result.appendSlice(allocator, value_str) catch return RenderError.OutOfMemory;
                }

                result.append(allocator, '}') catch return RenderError.OutOfMemory;
                break :blk result.toOwnedSlice(allocator) catch return RenderError.OutOfMemory;
            },
        };

        return Value.initString(json_str);
    }

    fn filterSha256(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(str, &hash, .{});

        // Convert to hex string manually
        var hex = self.workAllocator().alloc(u8, hash.len * 2) catch return RenderError.OutOfMemory;
        for (hash, 0..) |byte, i| {
            const hi = (byte >> 4) & 0xF;
            const lo = byte & 0xF;
            hex[i * 2] = if (hi < 10) '0' + hi else 'a' + hi - 10;
            hex[i * 2 + 1] = if (lo < 10) '0' + lo else 'a' + lo - 10;
        }

        return Value.initString(hex);
    }

    fn filterMd5(self: *Self, value: Value) RenderError!Value {
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;

        var hash: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(str, &hash, .{});

        // Convert to hex string manually
        var hex = self.workAllocator().alloc(u8, hash.len * 2) catch return RenderError.OutOfMemory;
        for (hash, 0..) |byte, i| {
            const hi = (byte >> 4) & 0xF;
            const lo = byte & 0xF;
            hex[i * 2] = if (hi < 10) '0' + hi else 'a' + hi - 10;
            hex[i * 2 + 1] = if (lo < 10) '0' + lo else 'a' + lo - 10;
        }

        return Value.initString(hex);
    }


    // Parse date strings like "March 14, 2016" into Unix timestamp
    fn parseDateStringToTimestamp(date_str: []const u8) !i64 {
        const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };

        var month_idx: usize = 0;
        for (months, 0..) |month, j| {
            if (std.mem.startsWith(u8, date_str, month)) {
                month_idx = j + 1;
                break;
            }
        }

        if (month_idx > 0) {
            var iter = std.mem.splitScalar(u8, date_str, ' ');
            _ = iter.next();
            const day_str = iter.next() orelse return RenderError.InvalidOperation;
            const year_str = iter.next() orelse return RenderError.InvalidOperation;

            const day_clean = if (day_str.len > 0 and day_str[day_str.len - 1] == ',')
                day_str[0 .. day_str.len - 1]
            else
                day_str;

            const day = std.fmt.parseInt(u8, day_clean, 10) catch return RenderError.InvalidOperation;
            const year = std.fmt.parseInt(i32, year_str, 10) catch return RenderError.InvalidOperation;

            // Use std.time.epoch to calculate timestamp
            const epoch = std.time.epoch;
            const year_num = @as(std.time.epoch.Year, @intCast(year));

            // Calculate days since epoch
            var days_since_epoch: i64 = 0;

            // Add full years
            var y: i32 = epoch.epoch_year;
            while (y < year) : (y += 1) {
                days_since_epoch += @as(i64, epoch.getDaysInYear(@as(std.time.epoch.Year, @intCast(y))));
            }

            // Add full months
            const month_enums = [_]std.time.epoch.Month{ .jan, .feb, .mar, .apr, .may, .jun, .jul, .aug, .sep, .oct, .nov, .dec };
            var m: usize = 0;
            while (m < month_idx - 1) : (m += 1) {
                days_since_epoch += @as(i64, epoch.getDaysInMonth(year_num, month_enums[m]));
            }

            // Add days
            days_since_epoch += @as(i64, day) - 1;

            return days_since_epoch * 86400;
        }

        return RenderError.InvalidOperation;
    }

    fn filterDate(self: *Self, value: Value, args: []const Node) RenderError!Value {
        // Date filter requires a format argument
        if (args.len == 0) return RenderError.InvalidOperation;

        // Get format string
        const fmt_node = args[0];
        const fmt_val = try self.evaluateNode(fmt_node);

        // If format is nil or empty, return original value
        if (fmt_val == .nil) return value;

        const format = fmt_val.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        if (format.len == 0) return value;

        // Try to parse as timestamp
        const seconds = switch (value) {
            .integer => |i| if (i >= 0) @as(i64, @intCast(i)) else return value,
            .string => |s| blk: {
                // First try to parse as integer timestamp
                const timestamp = std.fmt.parseInt(i64, s, 10) catch blk2: {
                    // If that fails, try parsing as date string like "March 14, 2016"
                    break :blk2 parseDateStringToTimestamp(s) catch return Value.initString(s);
                };
                if (timestamp < 0) return value;
                break :blk timestamp;
            },
            else => return value,
        };

        // Simple strftime implementation using std.time.epoch
        var result: std.ArrayList(u8) = .empty;

        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(seconds)) };
        const epoch_day = epoch_seconds.getEpochDay();
        const day_seconds = epoch_seconds.getDaySeconds();

        const year_and_day = epoch_day.calculateYearDay();
        const year = year_and_day.year;
        const month_and_day = year_and_day.calculateMonthDay();
        const month = month_and_day.month.numeric();
        const day = month_and_day.day_index + 1;

        const hour = day_seconds.getHoursIntoDay();
        const minute = day_seconds.getMinutesIntoHour();
        const second = day_seconds.getSecondsIntoMinute();

        var i: usize = 0;
        while (i < format.len) {
            if (format[i] == '%' and i + 1 < format.len) {
                const specifier = format[i + 1];
                i += 2;

                const replacement = switch (specifier) {
                    '%' => "%",
                    'a' => "Mon",
                    'b' => blk: {
                        const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
                        break :blk months[@as(usize, @intCast(std.math.clamp(month, 1, 12))) - 1];
                    },
                    'd' => std.fmt.allocPrint(self.workAllocator(), "{d:0>2}", .{day}) catch continue,
                    'e' => std.fmt.allocPrint(self.workAllocator(), "{d: >2}", .{day}) catch continue,
                    'H' => std.fmt.allocPrint(self.workAllocator(), "{d:0>2}", .{hour}) catch continue,
                    'M' => std.fmt.allocPrint(self.workAllocator(), "{d:0>2}", .{minute}) catch continue,
                    'S' => std.fmt.allocPrint(self.workAllocator(), "{d:0>2}", .{second}) catch continue,
                    'Y' => std.fmt.allocPrint(self.workAllocator(), "{d}", .{year}) catch continue,
                    'y' => std.fmt.allocPrint(self.workAllocator(), "{d:0>2}", .{@rem(year, 100)}) catch continue,
                    'm' => std.fmt.allocPrint(self.workAllocator(), "{d:0>2}", .{month}) catch continue,
                    's' => std.fmt.allocPrint(self.workAllocator(), "{d}", .{seconds}) catch continue,
                    else => continue,
                };

                try result.appendSlice(self.workAllocator(), replacement);
            } else {
                try result.append(self.workAllocator(), format[i]);
                i += 1;
            }
        }

        return Value.initString(try result.toOwnedSlice(self.workAllocator()));
    }

    fn filterFind(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;

        const key = try self.evaluateNode(args[0]);
        const key_str = key.toString(self.workAllocator()) catch return Value.initNil();

        // Optional second argument is the value to match
        const match_val: ?Value = if (args.len > 1) try self.evaluateNode(args[1]) else null;

        switch (value) {
            .string => |s| {
                // String input: check if contains key substring
                if (std.mem.indexOf(u8, s, key_str) != null) {
                    // If match_val provided, check it matches key_str too
                    if (match_val) |mv| {
                        const mv_str = mv.toString(self.workAllocator()) catch return Value.initNil();
                        if (!std.mem.eql(u8, key_str, mv_str)) {
                            return Value.initNil();
                        }
                    }
                    return value;
                }
                return Value.initNil();
            },
            .object => |obj| {
                // Hash input: check if has key (and optionally matches value)
                if (obj.get(key_str)) |found_val| {
                    if (match_val) |mv| {
                        if (found_val.eql(mv)) {
                            return value;
                        }
                        return Value.initNil();
                    }
                    return value;
                }
                return Value.initNil();
            },
            .array => |arr| {
                // For arrays, behavior depends on whether we have a value argument
                if (match_val) |mv| {
                    // find: 'key', value - search for object with key=value
                    for (arr) |item| {
                        if (item == .nil) return Value.initNil(); // nil breaks iteration
                        if (item == .object) {
                            if (item.object.get(key_str)) |found_val| {
                                if (found_val.eql(mv)) {
                                    return item;
                                }
                            }
                        }
                    }
                } else {
                    // find: 'search' - substring search in strings
                    for (arr) |item| {
                        if (item == .nil) return Value.initNil(); // nil breaks iteration
                        const item_str = item.toString(self.workAllocator()) catch continue;
                        if (std.mem.indexOf(u8, item_str, key_str) != null) {
                            return item;
                        }
                    }
                }
                return Value.initNil();
            },
            else => return Value.initNil(),
        }
    }

    fn filterFindIndex(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return Value.initNil();

        const key = try self.evaluateNode(args[0]);
        const key_str = key.toString(self.workAllocator()) catch return Value.initNil();

        // Check if second argument was explicitly provided
        const has_second_arg = args.len > 1;
        const match_val: Value = if (has_second_arg) try self.evaluateNode(args[1]) else Value.initNil();
        const match_val_is_nil = match_val == .nil;

        switch (value) {
            .string => |s| {
                // String input: check if contains key substring
                if (std.mem.indexOf(u8, s, key_str) != null) {
                    if (has_second_arg and !match_val_is_nil) {
                        const mv_str = match_val.toString(self.workAllocator()) catch return Value.initNil();
                        if (!std.mem.eql(u8, key_str, mv_str)) {
                            return Value.initNil();
                        }
                    }
                    return Value.initInt(0);
                }
                return Value.initNil();
            },
            .object => |obj| {
                // Hash input: check if has key
                if (obj.get(key_str)) |found_val| {
                    if (has_second_arg) {
                        if (match_val_is_nil) {
                            // find_index: 'key', nil - match if value is nil
                            // But this returns nil (not found) per the tests
                            return Value.initNil();
                        }
                        if (found_val.eql(match_val)) {
                            return Value.initInt(0);
                        }
                        return Value.initNil();
                    }
                    return Value.initInt(0);
                }
                return Value.initNil();
            },
            .array => |arr| {
                if (has_second_arg and !match_val_is_nil) {
                    for (arr, 0..) |item, i| {
                        if (item == .nil) return Value.initNil();
                        if (item == .object) {
                            if (item.object.get(key_str)) |found_val| {
                                if (found_val.eql(match_val)) {
                                    return Value.initInt(@intCast(i));
                                }
                            }
                        }
                    }
                } else if (has_second_arg and match_val_is_nil) {
                    // find_index: 'key', nil on array - returns nil per tests
                    return Value.initNil();
                } else {
                    for (arr, 0..) |item, i| {
                        if (item == .nil) return Value.initNil();
                        const item_str = item.toString(self.workAllocator()) catch continue;
                        if (std.mem.indexOf(u8, item_str, key_str) != null) {
                            return Value.initInt(@intCast(i));
                        }
                    }
                }
                return Value.initNil();
            },
            else => return Value.initNil(),
        }
    }

    fn filterHas(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return Value.initBool(false);

        const key = try self.evaluateNode(args[0]);

        // If key is not a string, return false (nil, int, bool, false as key all return false)
        const key_str: []const u8 = switch (key) {
            .string => |s| s,
            else => return Value.initBool(false),
        };

        // Check if second argument was explicitly provided
        const has_value_arg = args.len > 1;
        const match_val: Value = if (has_value_arg) try self.evaluateNode(args[1]) else Value.initNil();
        const match_val_is_nil = match_val == .nil;

        switch (value) {
            .string => |s| {
                // String input: check if contains key substring
                return Value.initBool(std.mem.indexOf(u8, s, key_str) != null);
            },
            .object => |obj| {
                // Hash input: check if has key (and optionally matches value)
                if (obj.get(key_str)) |found_val| {
                    if (has_value_arg) {
                        if (match_val_is_nil) {
                            // has: 'key', nil - check if value is NOT nil
                            return Value.initBool(found_val != .nil);
                        } else {
                            // Explicit value provided - check equality
                            return Value.initBool(found_val.eql(match_val));
                        }
                    }
                    return Value.initBool(true);
                }
                return Value.initBool(false);
            },
            .array => |arr| {
                if (has_value_arg) {
                    // has: 'key', value - search for object with key=value
                    for (arr) |item| {
                        if (item == .nil) return Value.initNil();
                        if (item == .object) {
                            if (item.object.get(key_str)) |found_val| {
                                if (match_val_is_nil) {
                                    // nil value arg means check if property is not nil
                                    if (found_val != .nil) {
                                        return Value.initBool(true);
                                    }
                                } else {
                                    if (found_val.eql(match_val)) {
                                        return Value.initBool(true);
                                    }
                                }
                            }
                        }
                    }
                    return Value.initBool(false);
                } else {
                    // has: 'search' - substring search in strings
                    for (arr) |item| {
                        if (item == .nil) return Value.initNil();
                        const item_str = item.toString(self.workAllocator()) catch continue;
                        if (std.mem.indexOf(u8, item_str, key_str) != null) {
                            return Value.initBool(true);
                        }
                    }
                    return Value.initBool(false);
                }
            },
            else => return Value.initBool(false),
        }
    }

    fn filterReject(self: *Self, value: Value, args: []const Node) RenderError!Value {
        if (args.len == 0) return value;

        const prop = try self.evaluateNode(args[0]);

        // If first argument is undefined/nil, return empty array
        if (prop == .nil) {
            return Value.initArray(&[_]Value{});
        }

        const prop_str: []const u8 = switch (prop) {
            .string => |s| s,
            else => return Value.initArray(&[_]Value{}),
        };

        const has_second_arg = args.len > 1;
        const match_val: Value = if (has_second_arg) try self.evaluateNode(args[1]) else Value.initNil();
        const match_val_is_nil = match_val == .nil;

        switch (value) {
            .array => |arr| {
                var result: std.ArrayList(Value) = .empty;
                var has_nil = false;
                self.rejectArrayRecursive(arr, prop_str, has_second_arg, match_val, match_val_is_nil, &result, &has_nil) catch return RenderError.OutOfMemory;
                if (has_nil) {
                    return Value.initNil();
                }
                return Value.initArray(result.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
            },
            .object => |obj| {
                // For hash, check if the specified key exists and matches criteria
                // If match found, reject entire hash. Otherwise return all pairs.
                var should_reject_all = false;

                if (obj.map.get(prop_str)) |val| {
                    if (has_second_arg) {
                        if (match_val_is_nil) {
                            // reject: 'key', nil - reject if value is truthy
                            should_reject_all = val.isTruthy();
                        } else {
                            // reject: 'key', value - reject if value equals match
                            should_reject_all = val.eql(match_val);
                        }
                    } else {
                        // reject: 'key' - reject if value is truthy
                        should_reject_all = val.isTruthy();
                    }
                }

                if (should_reject_all) {
                    return Value.initArray(&[_]Value{});
                }

                // No match found - return all pairs as [key, value] arrays
                var pairs: std.ArrayList(Value) = .empty;
                var it = obj.map.iterator();
                while (it.next()) |entry| {
                    var pair = self.workAllocator().alloc(Value, 2) catch return RenderError.OutOfMemory;
                    pair[0] = Value.initString(entry.key_ptr.*);
                    pair[1] = entry.value_ptr.*;
                    pairs.append(self.workAllocator(), Value.initArray(pair)) catch return RenderError.OutOfMemory;
                }
                return Value.initArray(pairs.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory);
            },
            .string => |s| {
                // String becomes single-element array
                if (std.mem.indexOf(u8, s, prop_str) != null) {
                    return Value.initArray(&[_]Value{});
                } else {
                    var result = self.workAllocator().alloc(Value, 1) catch return RenderError.OutOfMemory;
                    result[0] = value;
                    return Value.initArray(result);
                }
            },
            .nil => return Value.initArray(&[_]Value{}),
            else => return value,
        }
    }

    fn rejectArrayRecursive(
        self: *Self,
        arr: []const Value,
        prop_str: []const u8,
        has_second_arg: bool,
        match_val: Value,
        match_val_is_nil: bool,
        result: *std.ArrayList(Value),
        has_nil: *bool,
    ) RenderError!void {
        for (arr) |item| {
            switch (item) {
                .nil => {
                    has_nil.* = true;
                    return;
                },
                .array => |nested| {
                    // Flatten nested arrays
                    try self.rejectArrayRecursive(nested, prop_str, has_second_arg, match_val, match_val_is_nil, result, has_nil);
                    if (has_nil.*) return;
                },
                .object => {
                    // Check if should reject this object
                    const prop_val = item.get(prop_str) orelse Value.initNil();

                    var should_reject = false;
                    if (has_second_arg) {
                        if (match_val_is_nil) {
                            // reject: 'prop', nil - reject if property is truthy
                            should_reject = prop_val.isTruthy();
                        } else {
                            // reject: 'prop', value - reject if property equals value
                            should_reject = prop_val.eql(match_val);
                        }
                    } else {
                        // reject: 'prop' - reject if property is truthy
                        should_reject = prop_val.isTruthy();
                    }

                    if (!should_reject) {
                        result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                    }
                },
                .string => |s| {
                    // For strings, check substring match
                    if (std.mem.indexOf(u8, s, prop_str) == null) {
                        result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                    }
                },
                else => {
                    // Other types: check substring in string representation
                    const item_str = item.toString(self.workAllocator()) catch {
                        result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                        continue;
                    };
                    if (std.mem.indexOf(u8, item_str, prop_str) == null) {
                        result.append(self.workAllocator(), item) catch return RenderError.OutOfMemory;
                    }
                },
            }
        }
    }

    fn filterSum(self: *Self, value: Value) RenderError!Value {
        _ = self; // Mark as used
        if (value != .array) return Value.initInt(0);

        var sum: i64 = 0;
        for (value.array) |item| {
            switch (item) {
                .integer => |i| sum += i,
                .float => |f| sum += @as(i64, @intFromFloat(f)),
                else => {},
            }
        }

        return Value.initInt(sum);
    }

    // Tag rendering methods
    fn renderIfTag(self: *Self, node: Node) RenderError!void {
        if (node.children.items.len == 0) return;

        // First child is condition
        const condition = try self.evaluateNode(node.children.items[0]);

        if (condition.isTruthy()) {
            // Render body (skip condition and branch nodes)
            for (node.children.items[1..]) |child| {
                if (child.type == .elsif_branch or child.type == .else_branch) break;
                try self.renderNode(child);
            }
        } else {
            // Check for elsif/else branches
            for (node.children.items) |child| {
                if (child.type == .elsif_branch) {
                    if (child.children.items.len > 0) {
                        const elsif_cond = try self.evaluateNode(child.children.items[0]);
                        if (elsif_cond.isTruthy()) {
                            for (child.children.items[1..]) |sub_child| {
                                if (sub_child.type == .elsif_branch or sub_child.type == .else_branch) break;
                                try self.renderNode(sub_child);
                            }
                            return;
                        }
                    }
                } else if (child.type == .else_branch) {
                    for (child.children.items) |sub_child| {
                        try self.renderNode(sub_child);
                    }
                    return;
                }
            }
        }
    }

    fn renderUnlessTag(self: *Self, node: Node) RenderError!void {
        if (node.children.items.len == 0) return;

        // First child is condition
        const condition = try self.evaluateNode(node.children.items[0]);

        if (!condition.isTruthy()) {
            // Render body
            for (node.children.items[1..]) |child| {
                if (child.type == .else_branch) break;
                try self.renderNode(child);
            }
        } else {
            // Check for else branch
            for (node.children.items) |child| {
                if (child.type == .else_branch) {
                    for (child.children.items) |sub_child| {
                        try self.renderNode(sub_child);
                    }
                    return;
                }
            }
        }
    }

    fn renderForTag(self: *Self, node: Node) RenderError!void {
        if (node.children.items.len == 0) return;

        const loop_var = node.value orelse return;

        // First child is iterable
        const iterable = try self.evaluateNode(node.children.items[0]);

        // Parse optional parameters
        var limit: ?usize = null;
        var offset: usize = 0;
        var offset_continue = false;
        var reversed = false;

        for (node.children.items[1..]) |child| {
            if (child.type == .expression) {
                if (child.value) |param_name| {
                    if (std.mem.eql(u8, param_name, "limit")) {
                        if (child.children.items.len > 0) {
                            const l = try self.evaluateNode(child.children.items[0]);
                            limit = @intCast(switch (l) {
                                .integer => |i| if (i > 0) i else 0,
                                .string => |s| std.fmt.parseInt(i64, s, 10) catch 0,
                                else => 0,
                            });
                        }
                    } else if (std.mem.eql(u8, param_name, "offset")) {
                        if (child.children.items.len > 0) {
                            const o = try self.evaluateNode(child.children.items[0]);
                            switch (o) {
                                .integer => |i| offset = @intCast(if (i > 0) i else 0),
                                .string => |s| {
                                    if (std.mem.eql(u8, s, "continue")) {
                                        offset_continue = true;
                                        offset = 0;
                                    } else {
                                        const parsed = std.fmt.parseInt(i64, s, 10) catch 0;
                                        offset = @intCast(if (parsed > 0) parsed else 0);
                                    }
                                },
                                else => {
                                    if (child.children.items[0].type == .literal_string and
                                        child.children.items[0].value != null and
                                        std.mem.eql(u8, child.children.items[0].value.?, "continue"))
                                    {
                                        offset_continue = true;
                                    } else {
                                        offset = 0;
                                    }
                                },
                            }
                        } else if (child.value != null and std.mem.eql(u8, child.value.?, "continue")) {
                            offset_continue = true;
                        }
                    } else if (std.mem.eql(u8, param_name, "reversed")) {
                        reversed = true;
                    }
                }
            }
        }

        var continue_value_ptr: ?*usize = null;
        if (true) {
            const key_buf = try self.buildContinueKey(node.children.items[0]);
            const gop = try self.continue_offsets.getOrPut(key_buf);
            if (gop.found_existing) {
                self.allocator.free(key_buf);
            } else {
                gop.key_ptr.* = key_buf;
                gop.value_ptr.* = 0;
            }
            continue_value_ptr = gop.value_ptr;
        }

        if (offset_continue) {
            if (continue_value_ptr) |ptr| {
                offset = ptr.*;
            }
        }

        switch (iterable) {
            .array => |arr| {
                var items = arr;
                if (offset > 0 and offset < items.len) {
                    items = items[offset..];
                } else if (offset >= items.len) {
                    items = &[_]Value{};
                }

                if (limit) |l| {
                    if (l < items.len) {
                        items = items[0..l];
                    }
                }

                if (items.len == 0) {
                    // Render else branch if present
                    for (node.children.items) |child| {
                        if (child.type == .else_branch) {
                            for (child.children.items) |sub_child| {
                                try self.renderNode(sub_child);
                            }
                            return;
                        }
                    }
                    return;
                }

                const effective_len = items.len;
                var i: usize = 0;
                while (i < items.len) : (i += 1) {
                    const idx = if (reversed) items.len - 1 - i else i;
                    const item = items[idx];

                    // Set loop variable
                    self.local_vars.put(loop_var, item) catch return RenderError.OutOfMemory;

                    // Set forloop info
                    const info = ForloopInfo{
                        .index = i + 1,
                        .index0 = i,
                        .length = items.len,
                        .first = i == 0,
                        .last = i == items.len - 1,
                        .rindex = items.len - i,
                        .rindex0 = items.len - i - 1,
                    };
                    self.forloop_stack.append(self.allocator, info) catch return RenderError.OutOfMemory;

                    // Render body (skip iterable, params, and else)
                    for (node.children.items) |child| {
                        if (child.type == .expression or child.type == .else_branch) continue;
                        if (child.type == node.children.items[0].type and
                            std.meta.eql(child, node.children.items[0])) continue;

                        self.renderNode(child) catch |err| {
                            _ = self.forloop_stack.pop();
                            if (err == RenderError.BreakLoop) {
                                if (continue_value_ptr) |ptr| {
                                    ptr.* = offset + effective_len;
                                }
                                return;
                            }
                            if (err == RenderError.ContinueLoop) break;
                            return err;
                        };
                    }

                    _ = self.forloop_stack.pop();
                }

                if (continue_value_ptr) |ptr| {
                    ptr.* = offset + effective_len;
                }
            },
            .object => |obj| {
                // Convert object to array of [key, value] pairs for iteration
                var pairs: std.ArrayList(Value) = .empty;
                var iter = obj.map.iterator();
                while (iter.next()) |entry| {
                    var pair: std.ArrayList(Value) = .empty;
                    pair.append(self.workAllocator(), Value.initString(entry.key_ptr.*)) catch return RenderError.OutOfMemory;
                    pair.append(self.workAllocator(), entry.value_ptr.*) catch return RenderError.OutOfMemory;
                    pairs.append(self.workAllocator(), Value.initArray(pair.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory)) catch return RenderError.OutOfMemory;
                }

                var items = pairs.toOwnedSlice(self.workAllocator()) catch return RenderError.OutOfMemory;

                if (offset > 0 and offset < items.len) {
                    items = items[offset..];
                } else if (offset >= items.len) {
                    items = &[_]Value{};
                }

                if (limit) |l| {
                    if (l < items.len) {
                        items = items[0..l];
                    }
                }

                if (items.len == 0) {
                    // Render else branch if present
                    for (node.children.items) |child| {
                        if (child.type == .else_branch) {
                            for (child.children.items) |sub_child| {
                                try self.renderNode(sub_child);
                            }
                            return;
                        }
                    }
                    return;
                }

                const effective_len = items.len;
                var i: usize = 0;
                while (i < items.len) : (i += 1) {
                    const idx = if (reversed) items.len - 1 - i else i;
                    const item = items[idx];

                    // Set loop variable
                    self.local_vars.put(loop_var, item) catch return RenderError.OutOfMemory;

                    // Set forloop info
                    const info = ForloopInfo{
                        .index = i + 1,
                        .index0 = i,
                        .length = items.len,
                        .first = i == 0,
                        .last = i == items.len - 1,
                        .rindex = items.len - i,
                        .rindex0 = items.len - i - 1,
                    };
                    self.forloop_stack.append(self.allocator, info) catch return RenderError.OutOfMemory;

                    // Render body (skip iterable, params, and else)
                    for (node.children.items) |child| {
                        if (child.type == .expression or child.type == .else_branch) continue;
                        if (child.type == node.children.items[0].type and
                            std.meta.eql(child, node.children.items[0])) continue;

                        self.renderNode(child) catch |err| {
                            _ = self.forloop_stack.pop();
                            if (err == RenderError.BreakLoop) {
                                if (continue_value_ptr) |ptr| {
                                    ptr.* = offset + effective_len;
                                }
                                return;
                            }
                            if (err == RenderError.ContinueLoop) break;
                            return err;
                        };
                    }

                    _ = self.forloop_stack.pop();
                }

                if (continue_value_ptr) |ptr| {
                    ptr.* = offset + effective_len;
                }
            },
            else => {},
        }
    }

    fn renderAssignTag(self: *Self, node: Node) RenderError!void {
        const var_name = node.value orelse return;
        if (node.children.items.len == 0) return;

        // First child is the value expression
        var value = try self.evaluateNode(node.children.items[0]);

        // Apply filters
        for (node.children.items[1..]) |child| {
            if (child.type == .filter) {
                value = try self.applyFilter(value, child);
            }
        }

        self.local_vars.put(var_name, value) catch return RenderError.OutOfMemory;
    }

    fn renderCaptureTag(self: *Self, node: Node) RenderError!void {
        const var_name = node.value orelse return;

        // Save current output
        const saved_output = self.output;
        self.output = .empty;

        // Render body
        for (node.children.items) |child| {
            try self.renderNode(child);
        }

        // Get captured content
        const captured = self.output.toOwnedSlice(self.allocator) catch return RenderError.OutOfMemory;
        self.output = saved_output;

        // Set variable
        self.local_vars.put(var_name, Value.initString(captured)) catch return RenderError.OutOfMemory;
    }

    fn renderCaseTag(self: *Self, node: Node) RenderError!void {
        if (node.children.items.len == 0) return;

        const expr = try self.evaluateNode(node.children.items[0]);

        for (node.children.items[1..]) |child| {
            if (child.type == .when_branch) {
                // Check if any when value matches
                var matches = false;
                for (child.children.items) |when_val| {
                    if (when_val.type == .text or when_val.type == .output) continue;
                    const val = try self.evaluateNode(when_val);
                    if (expr.eql(val)) {
                        matches = true;
                        break;
                    }
                }

                if (matches) {
                    // Render when body
                    for (child.children.items) |sub_child| {
                        if (sub_child.type == .text or sub_child.type == .output or
                            sub_child.type == .if_tag or sub_child.type == .for_tag)
                        {
                            try self.renderNode(sub_child);
                        }
                    }
                    return;
                }
            } else if (child.type == .else_branch) {
                for (child.children.items) |sub_child| {
                    try self.renderNode(sub_child);
                }
                return;
            }
        }
    }

    fn renderCycleTag(self: *Self, node: Node) RenderError!void {
        if (node.children.items.len == 0) return;

        const group = node.value orelse "default";

        // Get or initialize cycle index
        const idx = self.cycle_indices.get(group) orelse 0;

        // Get the value at current index
        const values = node.children.items;
        const value = try self.evaluateNode(values[idx % values.len]);
        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        self.output.appendSlice(self.allocator, str) catch return RenderError.OutOfMemory;

        // Increment index
        self.cycle_indices.put(group, idx + 1) catch return RenderError.OutOfMemory;
    }

    fn renderIncrementTag(self: *Self, node: Node) RenderError!void {
        const var_name = node.value orelse return;

        const current = self.counters.get(var_name) orelse 0;
        const str = std.fmt.allocPrint(self.workAllocator(), "{d}", .{current}) catch return RenderError.OutOfMemory;
        self.output.appendSlice(self.allocator, str) catch return RenderError.OutOfMemory;
        const next = current + 1;
        self.counters.put(var_name, next) catch return RenderError.OutOfMemory;
        self.local_vars.put(var_name, Value.initInt(next)) catch return RenderError.OutOfMemory;
    }

    fn renderDecrementTag(self: *Self, node: Node) RenderError!void {
        const var_name = node.value orelse return;

        const current = self.counters.get(var_name) orelse 0;
        const new_val = current - 1;
        const str = std.fmt.allocPrint(self.workAllocator(), "{d}", .{new_val}) catch return RenderError.OutOfMemory;
        self.output.appendSlice(self.allocator, str) catch return RenderError.OutOfMemory;
        self.counters.put(var_name, new_val) catch return RenderError.OutOfMemory;
        self.local_vars.put(var_name, Value.initInt(new_val)) catch return RenderError.OutOfMemory;
    }

    fn renderTablerowTag(self: *Self, node: Node) RenderError!void {
        if (node.children.items.len == 0) return;

        const loop_var = node.value orelse return;
        const iterable = try self.evaluateNode(node.children.items[0]);

        var cols: usize = 0;
        var limit: ?usize = null;
        var offset: usize = 0;

        // Parse optional parameters
        for (node.children.items[1..]) |child| {
            if (child.type == .expression) {
                if (child.value) |param_name| {
                    if (std.mem.eql(u8, param_name, "cols")) {
                        if (child.children.items.len > 0) {
                            const c = try self.evaluateNode(child.children.items[0]);
                            cols = @intCast(switch (c) {
                                .integer => |i| if (i > 0) i else 0,
                                .string => |s| std.fmt.parseInt(i64, s, 10) catch 0,
                                else => 0,
                            });
                        }
                    } else if (std.mem.eql(u8, param_name, "limit")) {
                        if (child.children.items.len > 0) {
                            const l = try self.evaluateNode(child.children.items[0]);
                            limit = @intCast(switch (l) {
                                .integer => |i| if (i > 0) i else 0,
                                .string => |s| std.fmt.parseInt(i64, s, 10) catch 0,
                                else => 0,
                            });
                        }
                    } else if (std.mem.eql(u8, param_name, "offset")) {
                        if (child.children.items.len > 0) {
                            const o = try self.evaluateNode(child.children.items[0]);
                            offset = @intCast(switch (o) {
                                .integer => |i| if (i > 0) i else 0,
                                .string => |s| std.fmt.parseInt(i64, s, 10) catch 0,
                                else => 0,
                            });
                        }
                    }
                }
            }
        }

        switch (iterable) {
            .array => |arr| {
                var items = arr;
                if (offset > 0 and offset < items.len) {
                    items = items[offset..];
                } else if (offset >= items.len) {
                    items = &[_]Value{};
                }

                if (limit) |l| {
                    if (l < items.len) {
                        items = items[0..l];
                    }
                }

                if (cols == 0) {
                    cols = if (items.len > 0) items.len else 1;
                }

                var i: usize = 0;
                for (items) |item| {
                    if (i % cols == 0) {
                        if (i > 0) {
                            self.output.appendSlice(self.allocator, "</tr>\n") catch return RenderError.OutOfMemory;
                        }
                        const row_num = i / (if (cols > 0) cols else 1) + 1;
                        const row_str = std.fmt.allocPrint(self.allocator, "<tr class=\"row{d}\">\n", .{row_num}) catch return RenderError.OutOfMemory;
                        self.output.appendSlice(self.allocator, row_str) catch return RenderError.OutOfMemory;
                    }

                    const col_num = i % cols + 1;
                    const col_str = std.fmt.allocPrint(self.allocator, "<td class=\"col{d}\">", .{col_num}) catch return RenderError.OutOfMemory;
                    self.output.appendSlice(self.allocator, col_str) catch return RenderError.OutOfMemory;

                    self.local_vars.put(loop_var, item) catch return RenderError.OutOfMemory;

                    const info = TablerowInfo{
                        .col = col_num,
                        .col0 = col_num - 1,
                        .col_first = col_num == 1,
                        .col_last = col_num == cols or i == items.len - 1,
                        .row = i / cols + 1,
                        .index = i + 1,
                        .index0 = i,
                        .length = items.len,
                        .first = i == 0,
                        .last = i == items.len - 1,
                        .rindex = items.len - i,
                        .rindex0 = items.len - i - 1,
                    };
                    self.tablerow_stack.append(self.allocator, info) catch return RenderError.OutOfMemory;

                    // Render body
                    for (node.children.items) |child| {
                        if (child.type == .expression) continue;
                        if (child.type == node.children.items[0].type) continue;
                        self.renderNode(child) catch |err| {
                            _ = self.tablerow_stack.pop();
                            if (err == RenderError.BreakLoop) {
                                self.output.appendSlice(self.allocator, "</td></tr>\n") catch return RenderError.OutOfMemory;
                                return;
                            }
                            if (err == RenderError.ContinueLoop) break;
                            return err;
                        };
                    }

                    _ = self.tablerow_stack.pop();
                    self.output.appendSlice(self.allocator, "</td>") catch return RenderError.OutOfMemory;
                    i += 1;
                }

                if (i > 0) {
                    self.output.appendSlice(self.allocator, "</tr>\n") catch return RenderError.OutOfMemory;
                }
            },
            else => {},
        }
    }

    fn renderIncludeTag(self: *Self, node: Node) RenderError!void {
        try self.renderIncludeOrRender(node, false);
    }

    fn renderRenderTag(self: *Self, node: Node) RenderError!void {
        try self.renderIncludeOrRender(node, true);
    }

    fn renderIncludeOrRender(self: *Self, node: Node, isolate: bool) RenderError!void {
        if (node.children.items.len == 0) return;

        const template_val = try self.evaluateNode(node.children.items[0]);
        const template_name = template_val.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        const template_source = self.resolveTemplateSource(template_name) orelse return;

        var with_node: ?Node = null;
        var for_node: ?Node = null;

        var named_overrides: std.ArrayList(LocalOverride) = .empty;
        defer named_overrides.deinit(self.allocator);

        if (node.children.items.len > 1) {
            for (node.children.items[1..]) |child| {
                if (child.type != .expression or child.value == null) continue;
                const label = child.value.?;
                if (std.mem.eql(u8, label, "with")) {
                    with_node = child;
                } else if (std.mem.eql(u8, label, "for")) {
                    for_node = child;
                } else {
                    const val = if (child.children.items.len > 0)
                        try self.evaluateNode(child.children.items[0])
                    else
                        Value.initNil();
                    named_overrides.append(self.allocator, .{ .name = label, .value = val }) catch return RenderError.OutOfMemory;
                }
            }
        }

        var saved_local_vars: std.StringHashMap(Value) = undefined;
        var saved_counters: std.StringHashMap(i64) = undefined;
        var saved_cycle_indices: std.StringHashMap(usize) = undefined;
        var saved_forloop_stack: std.ArrayList(ForloopInfo) = undefined;
        if (isolate) {
            saved_local_vars = self.local_vars;
            self.local_vars = std.StringHashMap(Value).init(self.allocator);
            saved_counters = self.counters;
            self.counters = std.StringHashMap(i64).init(self.allocator);
            saved_cycle_indices = self.cycle_indices;
            self.cycle_indices = std.StringHashMap(usize).init(self.allocator);
            saved_forloop_stack = self.forloop_stack;
            self.forloop_stack = .empty;
        }
        defer if (isolate) {
            self.local_vars.deinit();
            self.local_vars = saved_local_vars;
            self.counters.deinit();
            self.counters = saved_counters;
            self.cycle_indices.deinit();
            self.cycle_indices = saved_cycle_indices;
            self.forloop_stack.deinit(self.allocator);
            self.forloop_stack = saved_forloop_stack;
        };

        if (for_node) |fnode| {
            if (fnode.children.items.len == 0) return;
            const iterable = try self.evaluateNode(fnode.children.items[0]);
            const var_name = fnode.filter_name orelse template_name;

            switch (iterable) {
                .array => |arr| {
                    const total = arr.len;
                    var i: usize = 0;
                    while (i < total) : (i += 1) {
                        const item = arr[i];
                        var overrides: std.ArrayList(LocalOverride) = .empty;
                        defer overrides.deinit(self.allocator);
                        overrides.appendSlice(self.allocator, named_overrides.items) catch return RenderError.OutOfMemory;
                        overrides.append(self.allocator, .{ .name = var_name, .value = item }) catch return RenderError.OutOfMemory;

                        var backups: std.ArrayList(LocalBackup) = .empty;
                        try self.applyOverrides(overrides.items, &backups);
                        defer self.restoreOverrides(&backups);

                        const info = ForloopInfo{
                            .index = i + 1,
                            .index0 = i,
                            .length = total,
                            .first = i == 0,
                            .last = i == total - 1,
                            .rindex = total - i,
                            .rindex0 = total - i - 1,
                        };
                        self.forloop_stack.append(self.allocator, info) catch return RenderError.OutOfMemory;
                        defer _ = self.forloop_stack.pop();

                        try self.renderTemplateSource(template_source);
                    }
                },
                else => {},
            }

            return;
        }

        var overrides: std.ArrayList(LocalOverride) = .empty;
        defer overrides.deinit(self.allocator);
        overrides.appendSlice(self.allocator, named_overrides.items) catch return RenderError.OutOfMemory;

        if (with_node) |wnode| {
            const val = if (wnode.children.items.len > 0)
                try self.evaluateNode(wnode.children.items[0])
            else
                Value.initNil();
            const var_name = wnode.filter_name orelse template_name;
            overrides.append(self.allocator, .{ .name = var_name, .value = val }) catch return RenderError.OutOfMemory;
        }

        var backups: std.ArrayList(LocalBackup) = .empty;
        try self.applyOverrides(overrides.items, &backups);
        defer self.restoreOverrides(&backups);

        try self.renderTemplateSource(template_source);
    }

    fn renderTemplateSource(self: *Self, source: []const u8) RenderError!void {
        var parser = parser_mod.Parser.init(self.allocator, source);
        defer parser.deinit();

        var ast = parser.parse() catch return RenderError.InvalidOperation;
        defer ast.deinit();

        for (ast.children.items) |child| {
            try self.renderNode(child);
        }
    }

    fn renderEchoTag(self: *Self, node: Node) RenderError!void {
        if (node.children.items.len == 0) return;

        var value = try self.evaluateNode(node.children.items[0]);

        // Apply filters
        for (node.children.items[1..]) |child| {
            if (child.type == .filter) {
                value = try self.applyFilter(value, child);
            }
        }

        const str = value.toString(self.workAllocator()) catch return RenderError.OutOfMemory;
        self.output.appendSlice(self.allocator, str) catch return RenderError.OutOfMemory;
    }

    fn renderIfchangedTag(self: *Self, node: Node) RenderError!void {
        // Simple implementation - just render the body for now
        for (node.children.items) |child| {
            try self.renderNode(child);
        }
    }
};

test "renderer simple output" {
    const allocator = std.testing.allocator;
    var parser = parser_mod.Parser.init(allocator, "{{ 'hello' }}");
    defer parser.deinit();

    var ast = parser.parse() catch unreachable;
    defer ast.deinit();

    var renderer = Renderer.init(allocator, Value.initNil());
    defer renderer.deinit();

    const result = renderer.render(ast) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello", result);
}

test "filter at_least with non-numeric string and negative min returns zero" {
    const allocator = std.testing.allocator;
    var parser = parser_mod.Parser.init(allocator, "{{ 'abc' | at_least: -5 }}");
    defer parser.deinit();

    var ast = parser.parse() catch unreachable;
    defer ast.deinit();

    var renderer = Renderer.init(allocator, Value.initNil());
    defer renderer.deinit();

    const result = renderer.render(ast) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualStrings("0", result);
}

test "liquid tag renders multiple statements" {
    const allocator = std.testing.allocator;
        const template =
            \\{% liquid
            \\  echo 'a'
            \\  echo 'b'
            \\%}
    ;
    var parser = parser_mod.Parser.init(allocator, template);
    defer parser.deinit();

    var ast = parser.parse() catch unreachable;
    defer ast.deinit();

    var renderer = Renderer.init(allocator, Value.initNil());
    defer renderer.deinit();

    const result = renderer.render(ast) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualStrings("ab", result);
}

test "for offset continue uses previous loop position" {
    const allocator = std.testing.allocator;
    const template = "{% assign nums = (1..4) %}{% for item in nums limit: 2 %}a{{ item }} {% endfor %}{% for item in nums offset: continue %}b{{ item }} {% endfor %}";
    var parser = parser_mod.Parser.init(allocator, template);
    defer parser.deinit();

    var ast = parser.parse() catch unreachable;
    defer ast.deinit();

    var renderer = Renderer.init(allocator, Value.initNil());
    defer renderer.deinit();

    const result = renderer.render(ast) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualStrings("a1 a2 b3 b4 ", result);
}

test "inline comment tag renders nothing" {
    const allocator = std.testing.allocator;
    var parser = parser_mod.Parser.init(allocator, "{%# some comment %}x");
    defer parser.deinit();

    var ast = parser.parse() catch unreachable;
    defer ast.deinit();

    var renderer = Renderer.init(allocator, Value.initNil());
    defer renderer.deinit();

    const result = renderer.render(ast) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualStrings("x", result);
}

test "include and render use templates from context" {
    const allocator = std.testing.allocator;
    const template =
        \\{% include 'snippet' %}
        \\{% render 'snippet' %}
    ;

    var templates = Value.initObject(allocator);
    try templates.object.put("snippet", Value.initString("hi"));
    defer templates.object.map.deinit();

    var context = Value.initObject(allocator);
    try context.object.put("__templates", templates);
    defer context.object.map.deinit();

    var parser = parser_mod.Parser.init(allocator, template);
    defer parser.deinit();

    var ast = parser.parse() catch unreachable;
    defer ast.deinit();

    var renderer = Renderer.init(allocator, context);
    defer renderer.deinit();

    const result = renderer.render(ast) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hi\nhi", result);
}
