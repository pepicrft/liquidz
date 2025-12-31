//! Liquid filters - Custom filter registry for extensibility
//!
//! Built-in filters are implemented in renderer.zig.
//! This module provides the FilterRegistry for registering custom filters.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;

pub const FilterError = error{
    OutOfMemory,
    InvalidArgument,
    TypeError,
};

/// Filter function signature for custom filters
/// Takes an allocator, input value, and filter arguments
/// Returns transformed value or error
pub const FilterFn = *const fn (Allocator, Value, []const Value) FilterError!Value;

/// Registry for custom filters that can be added at runtime
///
/// Example usage:
/// ```zig
/// var registry = FilterRegistry.init(allocator);
/// defer registry.deinit();
///
/// // Register a custom "shout" filter
/// try registry.register("shout", struct {
///     fn filter(alloc: Allocator, value: Value, _: []const Value) FilterError!Value {
///         const str = switch (value) {
///             .string => |s| s,
///             else => return value,
///         };
///         const upper = std.ascii.allocUpperString(alloc, str) catch return FilterError.OutOfMemory;
///         const result = std.fmt.allocPrint(alloc, "{s}!!!", .{upper}) catch return FilterError.OutOfMemory;
///         return Value.initString(result);
///     }
/// }.filter);
/// ```
pub const FilterRegistry = struct {
    allocator: Allocator,
    custom_filters: std.StringHashMap(FilterFn),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .custom_filters = std.StringHashMap(FilterFn).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free duplicated keys
        var it = self.custom_filters.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.custom_filters.deinit();
    }

    /// Register a custom filter
    /// The filter name is copied, so the caller can free their copy
    /// Custom filters take precedence over built-in filters with the same name
    pub fn register(self: *Self, name: []const u8, filter_fn: FilterFn) !void {
        // Duplicate the name so we own it
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        try self.custom_filters.put(owned_name, filter_fn);
    }

    /// Check if a custom filter is registered
    pub fn get(self: *const Self, name: []const u8) ?FilterFn {
        return self.custom_filters.get(name);
    }

    /// Apply a custom filter if registered, returns null if not found
    pub fn apply(
        self: *const Self,
        allocator: Allocator,
        filter_name: []const u8,
        value: Value,
        args: []const Value,
    ) ?FilterError!Value {
        if (self.custom_filters.get(filter_name)) |filter_fn| {
            return filter_fn(allocator, value, args);
        }
        return null;
    }
};
