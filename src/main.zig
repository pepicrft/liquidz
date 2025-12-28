//! Liquidz CLI - Liquid template rendering tool
//!
//! Usage: liquidz <template> [json-data]
//! Or read from stdin: echo "{{ name }}" | liquidz - '{"name": "World"}'

const std = @import("std");
const liquidz = @import("liquidz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    // Get template
    const template_arg = args[1];
    var template: []const u8 = undefined;

    if (std.mem.eql(u8, template_arg, "-")) {
        // Read from stdin
        template = try std.fs.File.stdin().readToEndAlloc(allocator, 1024 * 1024);
    } else if (std.mem.eql(u8, template_arg, "--help") or std.mem.eql(u8, template_arg, "-h")) {
        printUsage();
        return;
    } else {
        // Read from file
        const file = try std.fs.cwd().openFile(template_arg, .{});
        defer file.close();
        template = try file.readToEndAlloc(allocator, 1024 * 1024);
    }
    defer allocator.free(template);

    // Parse JSON data if provided
    var context = liquidz.Value.initNil();
    if (args.len >= 3) {
        context = try parseJsonToValue(allocator, args[2]);
    }
    defer (&context).deinit(allocator);

    // Render template
    const result = try liquidz.render(allocator, template, context);
    defer allocator.free(result);

    // Output result
    _ = try std.fs.File.stdout().write(result);
}

fn printUsage() void {
    std.debug.print(
        \\Liquidz - A Liquid template rendering tool
        \\
        \\Usage:
        \\  liquidz <template-file> [json-data]
        \\  liquidz - [json-data]              Read template from stdin
        \\  liquidz --help                     Show this help message
        \\
        \\Examples:
        \\  liquidz template.liquid '{{"name": "World"}}'
        \\  echo "Hello {{{{ name }}}}!" | liquidz - '{{"name": "World"}}'
        \\
    , .{});
}

fn parseJsonToValue(allocator: std.mem.Allocator, json_str: []const u8) !liquidz.Value {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch {
        return liquidz.Value.initNil();
    };
    defer parsed.deinit();

    // Copy all strings so we can free the JSON parse tree
    return jsonToValueCopy(allocator, parsed.value);
}

fn jsonToValueCopy(allocator: std.mem.Allocator, json: std.json.Value) !liquidz.Value {
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
                try result.append(allocator, try jsonToValueCopy(allocator, item));
            }
            break :blk liquidz.Value.initArray(try result.toOwnedSlice(allocator));
        },
        .object => |obj| blk: {
            var result = liquidz.Value.initObject(allocator);
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                try result.object.put(key_copy, try jsonToValueCopy(allocator, entry.value_ptr.*));
            }
            break :blk result;
        },
        .number_string => liquidz.Value.initNil(),
    };
}

fn jsonToValue(allocator: std.mem.Allocator, json: std.json.Value) !liquidz.Value {
    return switch (json) {
        .null => liquidz.Value.initNil(),
        .bool => |b| liquidz.Value.initBool(b),
        .integer => |i| liquidz.Value.initInt(i),
        .float => |f| liquidz.Value.initFloat(f),
        .string => |s| liquidz.Value.initString(s),
        .array => |arr| blk: {
            var result: std.ArrayList(liquidz.Value) = .empty;
            for (arr.items) |item| {
                try result.append(allocator, try jsonToValue(allocator, item));
            }
            break :blk liquidz.Value.initArray(try result.toOwnedSlice(allocator));
        },
        .object => |obj| blk: {
            var result = liquidz.Value.initObject(allocator);
            var it = obj.iterator();
            while (it.next()) |entry| {
                try result.object.put(entry.key_ptr.*, try jsonToValue(allocator, entry.value_ptr.*));
            }
            break :blk result;
        },
        .number_string => liquidz.Value.initNil(),
    };
}
