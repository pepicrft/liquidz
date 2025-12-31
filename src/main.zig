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
        const json_arg = args[2];
        // Check if it's a file path (starts with @ or ends with .json)
        if (json_arg.len > 0 and json_arg[0] == '@') {
            // Read JSON from file (e.g., @data.json)
            const file = try std.fs.cwd().openFile(json_arg[1..], .{});
            defer file.close();
            const json_data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
            defer allocator.free(json_data);
            context = try liquidz.Value.parseJson(allocator, json_data);
        } else {
            context = try liquidz.Value.parseJson(allocator, json_arg);
        }
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
