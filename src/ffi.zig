//! C ABI for Liquidz, intended for Ruby C extensions or other FFI callers.

const std = @import("std");
const liquidz = @import("root.zig");

const Allocator = std.mem.Allocator;

fn jsonToValueOwned(allocator: Allocator, json: std.json.Value) !liquidz.Value {
    return switch (json) {
        .null => liquidz.Value.initNil(),
        .bool => |b| liquidz.Value.initBool(b),
        .integer => |i| liquidz.Value.initInt(i),
        .float => |f| liquidz.Value.initFloat(f),
        .string => |s| blk: {
            const copy = try allocator.dupe(u8, s);
            break :blk liquidz.Value.initString(copy);
        },
        .array => |arr| blk: {
            var result: std.ArrayList(liquidz.Value) = .empty;
            for (arr.items) |item| {
                try result.append(allocator, try jsonToValueOwned(allocator, item));
            }
            break :blk liquidz.Value.initArray(try result.toOwnedSlice(allocator));
        },
        .object => |obj| blk: {
            var result = liquidz.Value.initObject(allocator);
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                try result.object.put(key_copy, try jsonToValueOwned(allocator, entry.value_ptr.*));
            }
            break :blk result;
        },
        .number_string => liquidz.Value.initNil(),
    };
}

fn renderFromJson(
    template: []const u8,
    json_data: []const u8,
    out_ptr: *[*]u8,
    out_len: *usize,
) !void {
    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var context = liquidz.Value.initNil();
    if (json_data.len > 0) {
        const parsed = try std.json.parseFromSlice(std.json.Value, arena_alloc, json_data, .{});
        context = try jsonToValueOwned(arena_alloc, parsed.value);
    }

    const rendered = try liquidz.render(allocator, template, context);
    out_ptr.* = @constCast(rendered.ptr);
    out_len.* = rendered.len;
}

pub export fn liquidz_render_json(
    template_ptr: [*]const u8,
    template_len: usize,
    json_ptr: [*]const u8,
    json_len: usize,
    out_ptr: *[*]u8,
    out_len: *usize,
) c_int {
    const template = template_ptr[0..template_len];
    const json_data = json_ptr[0..json_len];
    renderFromJson(template, json_data, out_ptr, out_len) catch return 1;
    return 0;
}

pub export fn liquidz_free(ptr: [*]u8, len: usize) void {
    std.heap.c_allocator.free(ptr[0..len]);
}
