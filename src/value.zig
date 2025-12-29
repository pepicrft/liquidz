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

    pub const ObjectMap = struct {
        allocator: Allocator,
        map: std.StringHashMap(Value),

        pub fn init(allocator: Allocator) ObjectMap {
            return .{
                .allocator = allocator,
                .map = std.StringHashMap(Value).init(allocator),
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

    /// Recursively free all memory owned by this value
    pub fn deinit(self: *Self, allocator: Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
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
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.*.deinit(allocator);
                }
                obj.map.deinit();
            },
            .nil, .boolean, .integer, .float => {},
        }
    }

    /// Check if the value is truthy (Liquid only considers nil and false as falsy)
    pub fn isTruthy(self: Self) bool {
        return switch (self) {
            .nil => false,
            .boolean => |b| b,
            // In Liquid, everything except nil and false is truthy
            .string, .array, .object, .integer, .float => true,
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
            .object => |obj| obj.get(key),
            .array => |arr| arrayGet(arr, std.fmt.parseInt(i64, key, 10) catch return null),
            else => null,
        };
    }

    /// Get array item by index
    pub fn getIndex(self: Self, idx: i64) ?Value {
        return switch (self) {
            .array => |arr| arrayGet(arr, idx),
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
                // Check if it's actually a whole number
                if (@round(f) == f and @abs(f) < 1e15) {
                    const int_val: i64 = @intFromFloat(f);
                    break :blk try std.fmt.allocPrint(allocator, "{d}.0", .{int_val});
                }

                // Format with high precision (15 decimal places for float64)
                const formatted = try std.fmt.allocPrint(allocator, "{d:.15}", .{f});

                // Trim trailing zeros after decimal point
                if (std.mem.indexOfScalar(u8, formatted, '.')) |dot_pos| {
                    var end = formatted.len;
                    while (end > dot_pos + 1 and formatted[end - 1] == '0') {
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
            .object => "{}",
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
        }
    }

    /// Check if value contains another value (for arrays or substrings)
    pub fn contains(self: Self, needle: Value) bool {
        switch (self) {
            .array => |arr| {
                for (arr) |item| {
                    if (item.eql(needle)) return true;
                }
                return false;
            },
            .string => |s| return needle == .string and std.mem.indexOf(u8, s, needle.string) != null,
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
