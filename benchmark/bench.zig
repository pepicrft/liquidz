//! Liquidz Benchmark Tool
//! Measures template rendering performance with pre-parsing (like Ruby does)

const std = @import("std");
const liquidz = @import("liquidz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: bench <template-file> <json-file> [iterations]\n", .{});
        return;
    }

    const iterations: usize = if (args.len >= 4)
        std.fmt.parseInt(usize, args[3], 10) catch 1000
    else
        1000;

    // Read template
    const template_file = try std.fs.cwd().openFile(args[1], .{});
    defer template_file.close();
    const template = try template_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(template);

    // Read JSON
    const json_file = try std.fs.cwd().openFile(args[2], .{});
    defer json_file.close();
    const json_data = try json_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(json_data);

    // Parse JSON once
    var context = try liquidz.Value.parseJson(allocator, json_data);
    defer (&context).deinit(allocator);

    // Pre-parse template once (like Ruby Liquid.parse does)
    var parser = liquidz.Parser.init(allocator, template);
    var ast = try parser.parse();
    defer ast.deinit();
    defer parser.deinit();

    // Warm up
    for (0..10) |_| {
        var renderer = liquidz.Renderer.init(allocator, context);
        const result = try renderer.render(ast);
        renderer.deinit();
        allocator.free(result);
    }

    // Benchmark (rendering only, not parsing)
    var total_ns: u64 = 0;
    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;

    for (0..iterations) |_| {
        const start = std.time.nanoTimestamp();

        var renderer = liquidz.Renderer.init(allocator, context);
        const result = try renderer.render(ast);
        renderer.deinit();
        allocator.free(result);

        const elapsed = @as(u64, @intCast(std.time.nanoTimestamp() - start));

        total_ns += elapsed;
        min_ns = @min(min_ns, elapsed);
        max_ns = @max(max_ns, elapsed);
    }

    const avg_us = total_ns / iterations / 1000;
    const min_us = min_ns / 1000;
    const max_us = max_ns / 1000;

    std.debug.print("Iterations: {d}\n", .{iterations});
    std.debug.print("Avg: {d} µs\n", .{avg_us});
    std.debug.print("Min: {d} µs\n", .{min_us});
    std.debug.print("Max: {d} µs\n", .{max_us});
}
