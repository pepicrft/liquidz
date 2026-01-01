//! WebAssembly FFI for Liquidz
//! Provides exported functions that can be called from JavaScript

const std = @import("std");
const liquidz = @import("liquidz");

// Use page allocator for WASM
const allocator = std.heap.wasm_allocator;

// Buffer for storing the result and error
var result_ptr: [*]u8 = undefined;
var result_len: usize = 0;
var error_ptr: [*]u8 = undefined;
var error_len: usize = 0;
var has_result: bool = false;
var has_error: bool = false;

/// Allocate memory for input data from JavaScript
export fn alloc(len: usize) ?[*]u8 {
    const slice = allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

/// Free memory allocated by alloc
export fn dealloc(ptr: [*]u8, len: usize) void {
    allocator.free(ptr[0..len]);
}

/// Get pointer to the result buffer
export fn get_result_ptr() ?[*]const u8 {
    if (has_result) {
        return result_ptr;
    }
    return null;
}

/// Get length of the result buffer
export fn get_result_len() usize {
    return result_len;
}

/// Get pointer to the error buffer
export fn get_error_ptr() ?[*]const u8 {
    if (has_error) {
        return error_ptr;
    }
    return null;
}

/// Get length of the error buffer
export fn get_error_len() usize {
    return error_len;
}

/// Free the result buffer
export fn free_result() void {
    if (has_result) {
        allocator.free(result_ptr[0..result_len]);
        has_result = false;
        result_len = 0;
    }
}

/// Free the error buffer
export fn free_error() void {
    if (has_error) {
        allocator.free(error_ptr[0..error_len]);
        has_error = false;
        error_len = 0;
    }
}

/// Render a Liquid template with JSON data
/// Returns 0 on success, 1 on error
/// Use get_result_ptr/get_result_len to get the result
/// Use get_error_ptr/get_error_len to get the error message
export fn render(
    template_ptr: [*]const u8,
    template_len: usize,
    json_ptr: [*]const u8,
    json_len: usize,
) i32 {
    // Clear previous buffers
    free_result();
    free_error();

    const template = template_ptr[0..template_len];
    const json_data = json_ptr[0..json_len];

    // Parse JSON context
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var context = liquidz.Value.initNil();
    if (json_len > 0) {
        context = liquidz.Value.parseJson(arena_alloc, json_data) catch {
            const msg = "JSON parse error";
            const err_buf = allocator.alloc(u8, msg.len) catch return 1;
            @memcpy(err_buf, msg);
            error_ptr = err_buf.ptr;
            error_len = err_buf.len;
            has_error = true;
            return 1;
        };
    }

    // Render template
    const rendered = liquidz.render(allocator, template, context) catch {
        const msg = "Render error";
        const err_buf = allocator.alloc(u8, msg.len) catch return 1;
        @memcpy(err_buf, msg);
        error_ptr = err_buf.ptr;
        error_len = err_buf.len;
        has_error = true;
        return 1;
    };

    result_ptr = @constCast(rendered.ptr);
    result_len = rendered.len;
    has_result = true;
    return 0;
}
