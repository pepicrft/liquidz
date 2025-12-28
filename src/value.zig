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

    const ObjectMap = struct {
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

    /// Check if the value is truthy (not nil and not false and not empty)
    pub fn isTruthy(self: Self) bool {
        return switch (self) {
            .nil => false,
            .boolean => |b| b,
            .string => |s| s.len > 0,
            .array => |arr| arr.len > 0,
            .object => |obj| obj.count() > 0,
            .integer, .float => true,
        };
    }

    /// Get a property from the value (for objects and arrays)
    pub fn get(self: Self, key: []const u8) ?Value {
        return switch (self) {
            .object => |obj| obj.get(key),
            .array => |arr| {
                const idx = std.fmt.parseInt(i64, key, 10) catch return null;
                if (idx < 0) {
                    const uidx = @as(usize, @intCast(-idx));
                    if (uidx > arr.len) return null;
                    return arr[arr.len - uidx];
                }
                const uidx = @as(usize, @intCast(idx));
                if (uidx >= arr.len) return null;
                return arr[uidx];
            },
            else => null,
        };
    }

    /// Get array item by index
    pub fn getIndex(self: Self, idx: i64) ?Value {
        return switch (self) {
            .array => |arr| {
                if (idx < 0) {
                    const uidx = @as(usize, @intCast(-idx));
                    if (uidx > arr.len) return null;
                    return arr[arr.len - uidx];
                }
                const uidx = @as(usize, @intCast(idx));
                if (uidx >= arr.len) return null;
                return arr[uidx];
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
        return switch (self) {
            .nil => other == .nil,
            .boolean => |b| switch (other) {
                .boolean => |ob| b == ob,
                else => false,
            },
            .integer => |i| switch (other) {
                .integer => |oi| i == oi,
                .float => |of| @as(f64, @floatFromInt(i)) == of,
                else => false,
            },
            .float => |f| switch (other) {
                .float => |of| f == of,
                .integer => |oi| f == @as(f64, @floatFromInt(oi)),
                else => false,
            },
            .string => |s| switch (other) {
                .string => |os| std.mem.eql(u8, s, os),
                else => false,
            },
            .array => |arr| switch (other) {
                .array => |oarr| {
                    if (arr.len != oarr.len) return false;
                    for (arr, oarr) |a, b| {
                        if (!a.eql(b)) return false;
                    }
                    return true;
                },
                else => false,
            },
            .object => false, // Object comparison not commonly needed
        };
    }

    /// Check if value contains another value (for arrays)
    pub fn contains(self: Self, needle: Value) bool {
        return switch (self) {
            .array => |arr| {
                for (arr) |item| {
                    if (item.eql(needle)) return true;
                }
                return false;
            },
            .string => |s| switch (needle) {
                .string => |ns| std.mem.indexOf(u8, s, ns) != null,
                else => false,
            },
            else => false,
        };
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
