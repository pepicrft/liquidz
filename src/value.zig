//! Value represents a Liquid value that can be used in templates.
//! It supports nil, booleans, integers, floats, strings, arrays, and objects.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    nil: void,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: []const Value,
    object: ObjectMap,
    empty: void, // Liquid's special empty value for comparison
    blank: void, // Liquid's special blank value for comparison
    range: Range, // Liquid range (start..end)
    liquid_error: []const u8, // Liquid error message to be rendered inline
    boolean_drop: BooleanDrop, // Special drop with separate truthiness and display value

    pub const Range = struct {
        start: i64,
        end: i64,
    };

    pub const BooleanDrop = struct {
        truthy: bool,
        display: []const u8,
    };

    pub const ObjectMap = struct {
        allocator: Allocator,
        // Use ArrayHashMap to preserve insertion order
        map: std.StringArrayHashMap(Value),

        pub fn init(allocator: Allocator) ObjectMap {
            return .{
                .allocator = allocator,
                .map = std.StringArrayHashMap(Value).init(allocator),
            };
        }

        pub fn put(self: *ObjectMap, key: []const u8, value: Value) !void {
            try self.map.put(key, value);
        }

        pub fn get(self: *const ObjectMap, key: []const u8) ?Value {
            return self.map.get(key);
        }

        pub fn count(self: *const ObjectMap) usize {
            return self.map.count();
        }
    };

    const Self = @This();

    pub fn initNil() Self {
        return .{ .nil = {} };
    }

    pub fn initBool(b: bool) Self {
        return .{ .boolean = b };
    }

    pub fn initInt(i: i64) Self {
        return .{ .integer = i };
    }

    pub fn initFloat(f: f64) Self {
        return .{ .float = f };
    }

    pub fn initString(s: []const u8) Self {
        return .{ .string = s };
    }

    pub fn initArray(arr: []const Value) Self {
        return .{ .array = arr };
    }

    pub fn initObject(allocator: Allocator) Self {
        return .{ .object = ObjectMap.init(allocator) };
    }

    pub fn initEmpty() Self {
        return .{ .empty = {} };
    }

    pub fn initBlank() Self {
        return .{ .blank = {} };
    }

    pub fn initRange(start: i64, end: i64) Self {
        return .{ .range = .{ .start = start, .end = end } };
    }

    pub fn initLiquidError(msg: []const u8) Self {
        return .{ .liquid_error = msg };
    }

    /// Recursively free memory owned by this value's containers (objects, arrays).
    ///
    /// Note: String values are NOT freed because `initString` stores borrowed slices,
    /// not owned copies. If you need owned strings, use `allocator.dupe()` when creating
    /// the Value and free them separately, or use an arena allocator for the entire
    /// render operation.
    ///
    /// For values created via `fromJson`, strings ARE copied and owned, but since we
    /// cannot distinguish owned from borrowed strings at runtime, callers using
    /// `fromJson` should use an arena allocator to handle cleanup.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        switch (self.*) {
            .string => {
                // Strings are not freed - they may be borrowed slices pointing to
                // template source, user data, or string literals. Freeing them would
                // cause crashes. Users should use arena allocators for owned strings.
            },
            .array => |arr| {
                for (arr) |*item| {
                    // Cast const to mutable - we own this memory and are freeing it
                    @constCast(item).deinit(allocator);
                }
                allocator.free(arr);
            },
            .object => |*obj| {
                var it = obj.map.iterator();
                while (it.next()) |entry| {
                    // Keys in StringArrayHashMap are also borrowed slices, not freed
                    entry.value_ptr.*.deinit(allocator);
                }
                obj.map.deinit();
            },
            .nil, .boolean, .integer, .float, .empty, .blank, .range, .liquid_error => {},
            .boolean_drop => {
                // Display string is borrowed, not freed
            },
        }
    }

    /// Check if the value is truthy (Liquid only considers nil and false as falsy)
    pub fn isTruthy(self: Self) bool {
        return switch (self) {
            .nil => false,
            .boolean => |b| b,
            // In Liquid, everything except nil and false is truthy
            // empty and blank are truthy when used as values
            .string, .array, .object, .integer, .float, .empty, .blank, .range => true,
            // Errors are truthy (they output something)
            .liquid_error => true,
            // Boolean drops use their truthy field
            .boolean_drop => |bd| bd.truthy,
        };
    }

    fn arrayGet(arr: []const Value, idx: i64) ?Value {
        if (idx < 0) {
            const uidx: usize = @intCast(-idx);
            return if (uidx > arr.len) null else arr[arr.len - uidx];
        }
        const uidx: usize = @intCast(idx);
        return if (uidx >= arr.len) null else arr[uidx];
    }

    /// Get a property from the value (for objects and arrays)
    pub fn get(self: Self, key: []const u8) ?Value {
        return switch (self) {
            .object => |obj| {
                // First try regular property lookup (most common case)
                if (obj.get(key)) |v| return v;

                // Special property 'size' for objects (only if not shadowed)
                // Check length first to avoid full string comparison
                if (key.len == 4 and std.mem.eql(u8, key, "size")) {
                    return Self.initInt(@intCast(obj.count()));
                }
                // 'first' and 'last' on objects require allocator - not supported here
                return null;
            },
            .array => |arr| {
                // Fast path: try numeric index first (most common case)
                if (key.len > 0 and (key[0] >= '0' and key[0] <= '9' or key[0] == '-')) {
                    if (std.fmt.parseInt(i64, key, 10)) |idx| {
                        return arrayGet(arr, idx);
                    } else |_| {}
                }
                // Special properties for arrays (less common)
                if (key.len == 4 and std.mem.eql(u8, key, "size")) {
                    return Self.initInt(@intCast(arr.len));
                } else if (key.len == 5 and std.mem.eql(u8, key, "first")) {
                    return if (arr.len > 0) arr[0] else null;
                } else if (key.len == 4 and std.mem.eql(u8, key, "last")) {
                    return if (arr.len > 0) arr[arr.len - 1] else null;
                }
                return null;
            },
            .string => |s| {
                // Special properties for strings
                if (std.mem.eql(u8, key, "size")) {
                    return Self.initInt(@intCast(s.len));
                }
                return null;
            },
            .range => |r| {
                // Special properties for ranges
                if (std.mem.eql(u8, key, "first")) {
                    return Self.initInt(r.start);
                } else if (std.mem.eql(u8, key, "last")) {
                    return Self.initInt(r.end);
                } else if (std.mem.eql(u8, key, "size")) {
                    return Self.initInt(if (r.end >= r.start) r.end - r.start + 1 else 0);
                }
                return null;
            },
            else => null,
        };
    }

    /// Get array item by index (also works for strings to get characters)
    pub fn getIndex(self: Self, idx: i64) ?Value {
        return switch (self) {
            .array => |arr| arrayGet(arr, idx),
            .string => |s| {
                if (idx < 0) {
                    const uidx: usize = @intCast(-idx);
                    return if (uidx > s.len) null else Self.initString(s[s.len - uidx ..][0..1]);
                }
                const uidx: usize = @intCast(idx);
                return if (uidx >= s.len) null else Self.initString(s[uidx..][0..1]);
            },
            else => null,
        };
    }

    /// Convert value to string for output
    pub fn toString(self: Self, allocator: Allocator) ![]const u8 {
        return switch (self) {
            .nil => "",
            .boolean => |b| if (b) "true" else "false",
            .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float => |f| blk: {
                const abs_f = @abs(f);

                // For very large numbers, use scientific notation
                if (abs_f >= 1e15) {
                    const formatted = try std.fmt.allocPrint(allocator, "{e:.1}", .{f});
                    break :blk formatted;
                }

                // For very small non-zero numbers, check if they're "clean" powers of 10
                // vs floating point precision errors
                if (abs_f != 0 and abs_f < 1e-4) {
                    // Check if this looks like a precision error (not a clean mantissa)
                    // by seeing if it rounds to a clean value
                    const log10_val = @log10(abs_f);
                    const exponent = @floor(log10_val);
                    const mantissa = abs_f / std.math.pow(f64, 10.0, exponent);
                    // If mantissa is close to 1 (within 1%), it's a clean power of 10
                    const is_clean = @abs(mantissa - @round(mantissa)) < 0.01;

                    if (is_clean) {
                        // Use scientific notation for clean small values
                        const formatted = try std.fmt.allocPrint(allocator, "{e:.1}", .{f});
                        break :blk formatted;
                    } else {
                        // Likely a floating point error, round to zero
                        break :blk try std.fmt.allocPrint(allocator, "0.0", .{});
                    }
                }

                // Format with high precision first
                const formatted = try std.fmt.allocPrint(allocator, "{d:.15}", .{f});

                // Find the decimal point
                if (std.mem.indexOfScalar(u8, formatted, '.')) |dot_pos| {
                    // Check for floating point artifacts: long strings of 9s or 0s
                    // e.g., "7.249999999999999" should become "7.25"
                    // e.g., "12.000000000000000" should become "12.0"
                    // Look for patterns like "99999" or "00000" (5+ repeated digits) at the end
                    var nine_count: usize = 0;
                    var zero_count: usize = 0;
                    var pattern_break_pos: usize = formatted.len;

                    var i: usize = formatted.len;
                    while (i > dot_pos + 1) {
                        i -= 1;
                        if (formatted[i] == '9') {
                            nine_count += 1;
                            zero_count = 0;
                        } else if (formatted[i] == '0') {
                            zero_count += 1;
                            nine_count = 0;
                        } else {
                            if (nine_count >= 5 or zero_count >= 5) {
                                // Found a pattern ending at position i+1, round at position i
                                const precision = i - dot_pos;
                                const multiplier = std.math.pow(f64, 10.0, @floatFromInt(precision));
                                const rounded = @round(f * multiplier) / multiplier;

                                // Check if it's a whole number
                                if (@round(rounded) == rounded and @abs(rounded) < 1e15) {
                                    const int_val: i64 = @intFromFloat(rounded);
                                    allocator.free(formatted);
                                    break :blk try std.fmt.allocPrint(allocator, "{d}.0", .{int_val});
                                }

                                // Format the rounded value and trim trailing zeros
                                allocator.free(formatted);
                                const rounded_fmt = try std.fmt.allocPrint(allocator, "{d:.15}", .{rounded});

                                if (std.mem.indexOfScalar(u8, rounded_fmt, '.')) |rdot| {
                                    var rend = rounded_fmt.len;
                                    while (rend > rdot + 2 and rounded_fmt[rend - 1] == '0') {
                                        rend -= 1;
                                    }
                                    if (rend != rounded_fmt.len) {
                                        const trimmed = try allocator.alloc(u8, rend);
                                        @memcpy(trimmed, rounded_fmt[0..rend]);
                                        allocator.free(rounded_fmt);
                                        break :blk trimmed;
                                    }
                                }
                                break :blk rounded_fmt;
                            }
                            pattern_break_pos = i;
                            nine_count = 0;
                            zero_count = 0;
                        }
                    }

                    // Check if entire decimal part is 9s or 0s
                    if (nine_count >= 5 or zero_count >= 5) {
                        const rounded = @round(f);
                        if (@abs(rounded) < 1e15) {
                            const int_val: i64 = @intFromFloat(rounded);
                            allocator.free(formatted);
                            break :blk try std.fmt.allocPrint(allocator, "{d}.0", .{int_val});
                        }
                    }

                    // No pattern found, just trim trailing zeros (keep at least one after decimal)
                    var end = formatted.len;
                    while (end > dot_pos + 2 and formatted[end - 1] == '0') {
                        end -= 1;
                    }
                    if (end != formatted.len) {
                        const trimmed = try allocator.alloc(u8, end);
                        @memcpy(trimmed, formatted[0..end]);
                        allocator.free(formatted);
                        break :blk trimmed;
                    }
                }
                break :blk formatted;
            },
            .string => |s| s,
            .array => |arr| {
                var result: std.ArrayList(u8) = .empty;
                for (arr, 0..) |item, i| {
                    if (i > 0) try result.appendSlice(allocator, "");
                    const s = try item.toString(allocator);
                    try result.appendSlice(allocator, s);
                }
                return result.toOwnedSlice(allocator);
            },
            .object => |obj| {
                // Check for recursive hash marker
                if (obj.map.get("_liquidz_recursive")) |_| {
                    return try allocator.dupe(u8, "{...}");
                }
                // Check for custom to_s (hash with custom string representation)
                if (obj.map.get("_liquidz_custom_to_s")) |custom_to_s| {
                    if (custom_to_s == .string) {
                        return try allocator.dupe(u8, custom_to_s.string);
                    }
                }
                // Check for special _liquidz_symbol object (Ruby symbol)
                if (obj.map.get("_liquidz_symbol")) |_| {
                    if (obj.map.get("name")) |name_val| {
                        if (name_val == .string) {
                            return try std.fmt.allocPrint(allocator, ":{s}", .{name_val.string});
                        }
                    }
                }
                // Format as Ruby hash: {"key"=>value, ...}
                var result: std.ArrayList(u8) = .empty;
                try result.append(allocator, '{');
                var first = true;
                var iter = obj.map.iterator();
                while (iter.next()) |entry| {
                    const key = entry.key_ptr.*;
                    // Skip internal marker keys
                    if (std.mem.eql(u8, key, "_liquidz_has_symbol_keys")) continue;
                    if (std.mem.eql(u8, key, "_liquidz_has_hash_keys")) continue;
                    if (!first) try result.appendSlice(allocator, ", ");
                    first = false;
                    // Check if key is a symbol (starts with :)
                    if (key.len > 0 and key[0] == ':') {
                        // Render as symbol: :key (no quotes)
                        try result.appendSlice(allocator, key);
                    } else if (std.mem.startsWith(u8, key, "_liquidz_hash_key:")) {
                        // Hash key - render without quotes, strip the prefix
                        try result.appendSlice(allocator, key["_liquidz_hash_key:".len..]);
                    } else {
                        // Quote the key
                        try result.append(allocator, '"');
                        try result.appendSlice(allocator, key);
                        try result.append(allocator, '"');
                    }
                    try result.appendSlice(allocator, "=>");
                    // Format the value
                    const val = entry.value_ptr.*;
                    switch (val) {
                        .string => |s| {
                            try result.append(allocator, '"');
                            try result.appendSlice(allocator, s);
                            try result.append(allocator, '"');
                        },
                        .array => {
                            try result.append(allocator, '[');
                            var first_item = true;
                            for (val.array) |item| {
                                if (!first_item) try result.appendSlice(allocator, ", ");
                                first_item = false;
                                switch (item) {
                                    .string => |s| {
                                        try result.append(allocator, '"');
                                        try result.appendSlice(allocator, s);
                                        try result.append(allocator, '"');
                                    },
                                    else => {
                                        const s = try item.toString(allocator);
                                        try result.appendSlice(allocator, s);
                                    },
                                }
                            }
                            try result.append(allocator, ']');
                        },
                        else => {
                            const s = try val.toString(allocator);
                            try result.appendSlice(allocator, s);
                        },
                    }
                }
                try result.append(allocator, '}');
                return result.toOwnedSlice(allocator);
            },
            .empty, .blank => "",
            .range => |r| try std.fmt.allocPrint(allocator, "{d}..{d}", .{ r.start, r.end }),
            .liquid_error => |msg| msg,
            .boolean_drop => |bd| bd.display,
        };
    }

    /// Get the size/length of the value
    pub fn size(self: Self) i64 {
        return switch (self) {
            .string => |s| @intCast(s.len),
            .array => |arr| @intCast(arr.len),
            .object => |obj| @intCast(obj.count()),
            else => 0,
        };
    }

    /// Compare two values for equality
    pub fn eql(self: Self, other: Self) bool {
        // In Ruby Liquid, empty == empty and blank == blank are always false
        if (self == .empty and other == .empty) return false;
        if (self == .blank and other == .blank) return false;

        // Handle special 'empty' comparison (comparing non-empty values against empty literal)
        if (other == .empty) {
            return self.isEmpty();
        }
        if (self == .empty) {
            return other.isEmpty();
        }
        // Handle special 'blank' comparison (comparing non-blank values against blank literal)
        if (other == .blank) {
            return self.isBlank();
        }
        if (self == .blank) {
            return other.isBlank();
        }

        switch (self) {
            .nil => return other == .nil,
            .boolean => |b| return other == .boolean and b == other.boolean,
            .integer => |i| return switch (other) {
                .integer => |oi| i == oi,
                .float => |of| @as(f64, @floatFromInt(i)) == of,
                else => false,
            },
            .float => |f| return switch (other) {
                .float => |of| f == of,
                .integer => |oi| f == @as(f64, @floatFromInt(oi)),
                else => false,
            },
            .string => |s| return other == .string and std.mem.eql(u8, s, other.string),
            .array => |arr| {
                if (other != .array or arr.len != other.array.len) return false;
                for (arr, other.array) |a, b| {
                    if (!a.eql(b)) return false;
                }
                return true;
            },
            .object => return false,
            .empty, .blank => return false,
            .range => |r| return other == .range and r.start == other.range.start and r.end == other.range.end,
            .liquid_error => |msg| return other == .liquid_error and std.mem.eql(u8, msg, other.liquid_error),
            .boolean_drop => |bd| return other == .boolean_drop and bd.truthy == other.boolean_drop.truthy and std.mem.eql(u8, bd.display, other.boolean_drop.display),
        }
    }

    /// Check if value is empty (empty array, empty object, empty string, or nil)
    pub fn isEmpty(self: Self) bool {
        return switch (self) {
            .array => |arr| arr.len == 0,
            .object => |obj| obj.count() == 0,
            .string => |s| s.len == 0,
            .nil => true,
            .empty => true,
            else => false,
        };
    }

    /// Check if value is blank (empty, nil, or whitespace-only string)
    pub fn isBlank(self: Self) bool {
        return switch (self) {
            .array => |arr| arr.len == 0,
            .object => |obj| obj.count() == 0,
            .string => |s| blk: {
                for (s) |c| {
                    if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                        break :blk false;
                    }
                }
                break :blk true;
            },
            .nil => true,
            .blank => true,
            .empty => true,
            else => false,
        };
    }

    /// Get the type name for error messages
    pub fn typeName(self: Self) []const u8 {
        return switch (self) {
            .nil => "NilClass",
            .boolean => "Boolean",
            .integer => "Integer",
            .float => "Float",
            .string => "String",
            .array => "Array",
            .object => "Hash",
            .range => "Range",
            .empty => "Empty",
            .blank => "Blank",
            .liquid_error => "Error",
            .boolean_drop => "BooleanDrop",
        };
    }

    /// Check if value contains another value (for arrays or substrings)
    /// Note: In Liquid, contains with nil/false as needle always returns false
    pub fn contains(self: Self, needle: Value) bool {
        // In Liquid, contains with nil or false as needle always returns false
        if (needle == .nil or (needle == .boolean and !needle.boolean)) {
            return false;
        }

        switch (self) {
            .array => |arr| {
                for (arr) |item| {
                    if (item.eql(needle)) return true;
                }
                return false;
            },
            .string => |s| {
                // For string contains, convert needle to string and check
                if (needle == .string) {
                    return std.mem.indexOf(u8, s, needle.string) != null;
                }
                if (needle == .integer) {
                    // Convert integer to string and check
                    var buf: [32]u8 = undefined;
                    const int_str = std.fmt.bufPrint(&buf, "{d}", .{needle.integer}) catch return false;
                    return std.mem.indexOf(u8, s, int_str) != null;
                }
                return false;
            },
            else => return false,
        }
    }

    /// Convert a std.json.Value to a liquidz Value, copying all strings
    pub fn fromJson(allocator: Allocator, json: std.json.Value) !Self {
        return switch (json) {
            .null => Self.initNil(),
            .bool => |b| Self.initBool(b),
            .integer => |i| Self.initInt(i),
            .float => |f| Self.initFloat(f),
            .string => |s| Self.initString(try allocator.dupe(u8, s)),
            .array => |arr| blk: {
                var result: std.ArrayList(Self) = .empty;
                for (arr.items) |item| {
                    try result.append(allocator, try fromJson(allocator, item));
                }
                break :blk Self.initArray(try result.toOwnedSlice(allocator));
            },
            .object => |obj| blk: {
                // Check for special _liquidz_range encoding
                if (obj.get("_liquidz_range")) |_| {
                    const start_json = obj.get("start") orelse break :blk Self.initNil();
                    const end_json = obj.get("end") orelse break :blk Self.initNil();
                    const start: i64 = switch (start_json) {
                        .integer => |i| i,
                        .float => |f| @intFromFloat(f),
                        else => 0,
                    };
                    const end: i64 = switch (end_json) {
                        .integer => |i| i,
                        .float => |f| @intFromFloat(f),
                        else => 0,
                    };
                    break :blk Self.initRange(start, end);
                }

                // Check for special _liquidz_boolean_drop encoding
                if (obj.get("_liquidz_boolean_drop")) |_| {
                    const truthy_json = obj.get("truthy") orelse break :blk Self.initNil();
                    const display_json = obj.get("display") orelse break :blk Self.initNil();
                    const truthy: bool = switch (truthy_json) {
                        .bool => |b| b,
                        else => false,
                    };
                    const display: []const u8 = switch (display_json) {
                        .string => |s| try allocator.dupe(u8, s),
                        else => "",
                    };
                    break :blk Self{ .boolean_drop = .{ .truthy = truthy, .display = display } };
                }

                var result = Self.initObject(allocator);
                var it = obj.iterator();
                while (it.next()) |entry| {
                    const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                    try result.object.put(key_copy, try fromJson(allocator, entry.value_ptr.*));
                }
                break :blk result;
            },
            .number_string => Self.initNil(),
        };
    }

    /// Parse a JSON string and convert to Value
    pub fn parseJson(allocator: Allocator, json_str: []const u8) !Self {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch {
            return Self.initNil();
        };
        defer parsed.deinit();
        return fromJson(allocator, parsed.value);
    }

    /// Check if value is nil
    pub fn isNil(self: Self) bool {
        return self == .nil;
    }

    /// Convert value to integer if possible
    pub fn toInt(self: Self) ?i64 {
        return switch (self) {
            .integer => |i| i,
            .float => |f| @intFromFloat(f),
            .string => |s| std.fmt.parseInt(i64, s, 10) catch null,
            else => null,
        };
    }

    /// Convert value to float if possible
    pub fn toFloat(self: Self) ?f64 {
        return switch (self) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            .string => |s| std.fmt.parseFloat(f64, s) catch null,
            else => null,
        };
    }

    /// Get string representation (for filter string arguments)
    pub fn toDisplayString(self: Self, allocator: Allocator) ![]const u8 {
        return self.toString(allocator);
    }

    /// Convert value to JSON string
    pub fn toJsonString(self: Self, allocator: Allocator) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        try self.writeJson(allocator, &result);
        return result.toOwnedSlice(allocator);
    }

    fn writeJson(self: Self, allocator: Allocator, result: *std.ArrayList(u8)) !void {
        switch (self) {
            .nil => try result.appendSlice(allocator, "null"),
            .boolean => |b| try result.appendSlice(allocator, if (b) "true" else "false"),
            .integer => |i| {
                const s = try std.fmt.allocPrint(allocator, "{d}", .{i});
                defer allocator.free(s);
                try result.appendSlice(allocator, s);
            },
            .float => |f| {
                const s = try std.fmt.allocPrint(allocator, "{d}", .{f});
                defer allocator.free(s);
                try result.appendSlice(allocator, s);
            },
            .string => |s| {
                try result.append(allocator, '"');
                for (s) |c| {
                    switch (c) {
                        '"' => try result.appendSlice(allocator, "\\\""),
                        '\\' => try result.appendSlice(allocator, "\\\\"),
                        '\n' => try result.appendSlice(allocator, "\\n"),
                        '\r' => try result.appendSlice(allocator, "\\r"),
                        '\t' => try result.appendSlice(allocator, "\\t"),
                        else => try result.append(allocator, c),
                    }
                }
                try result.append(allocator, '"');
            },
            .array => |arr| {
                try result.append(allocator, '[');
                for (arr, 0..) |item, i| {
                    if (i > 0) try result.append(allocator, ',');
                    try item.writeJson(allocator, result);
                }
                try result.append(allocator, ']');
            },
            .object => |obj| {
                try result.append(allocator, '{');
                var first = true;
                var iter = obj.map.iterator();
                while (iter.next()) |entry| {
                    if (!first) try result.append(allocator, ',');
                    first = false;
                    try result.append(allocator, '"');
                    try result.appendSlice(allocator, entry.key_ptr.*);
                    try result.appendSlice(allocator, "\":");
                    try entry.value_ptr.writeJson(allocator, result);
                }
                try result.append(allocator, '}');
            },
            .empty, .blank => try result.appendSlice(allocator, "null"),
            .range => |r| {
                const s = try std.fmt.allocPrint(allocator, "[{d},{d}]", .{ r.start, r.end });
                defer allocator.free(s);
                try result.appendSlice(allocator, s);
            },
            .liquid_error => |e| {
                try result.append(allocator, '"');
                try result.appendSlice(allocator, e);
                try result.append(allocator, '"');
            },
            .boolean_drop => |bd| {
                try result.append(allocator, '"');
                try result.appendSlice(allocator, bd.display);
                try result.append(allocator, '"');
            },
        }
    }
};

test "value truthy" {
    try std.testing.expect(!Value.initNil().isTruthy());
    try std.testing.expect(!Value.initBool(false).isTruthy());
    try std.testing.expect(Value.initBool(true).isTruthy());
    try std.testing.expect(Value.initInt(0).isTruthy());
    try std.testing.expect(Value.initString("").isTruthy());
}

test "value equality" {
    try std.testing.expect(Value.initInt(42).eql(Value.initInt(42)));
    try std.testing.expect(Value.initString("hello").eql(Value.initString("hello")));
    try std.testing.expect(!Value.initInt(42).eql(Value.initInt(43)));
}
