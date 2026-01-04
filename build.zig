const std = @import("std");

pub fn build(b: *std.Build) void {
     const target = b.standardTargetOptions(.{});
     const optimize = b.standardOptimizeOption(.{});

    // Create the liquidz module
    const liquidz_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Check if we're building for WASM
    const is_wasm = target.result.cpu.arch == .wasm32 or target.result.cpu.arch == .wasm64;

    // Check if we're building for Apple embedded platforms (no executables allowed)
    const is_apple_embedded = target.result.os.tag == .ios or
        target.result.os.tag == .tvos or
        target.result.os.tag == .watchos or
        target.result.os.tag == .visionos;

    // Executable (skip for WASM and Apple embedded platforms)
    var exe: ?*std.Build.Step.Compile = null;
    if (!is_wasm and !is_apple_embedded and target.result.os.tag != .freestanding) {
        const exe_val = b.addExecutable(.{
            .name = "liquidz",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "liquidz", .module = liquidz_mod },
                },
            }),
        });
        b.installArtifact(exe_val);
        exe = exe_val;
    }

    // Check if we're building for a target that supports FFI (skip for WASM)
    const is_native_compatible = !is_wasm and target.result.os.tag != .freestanding;

    // C ABI static library for Ruby/Node.js/Elixir integration (skip for WASM)
    if (is_native_compatible) {
        const ffi_lib = b.addLibrary(.{
            .name = "liquidz_ffi",
            .linkage = .static,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/ffi.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "liquidz", .module = liquidz_mod },
                },
            }),
        });
        ffi_lib.linkLibC();
        b.installArtifact(ffi_lib);
    }

    // C ABI dynamic/shared library for Python/Deno FFI integration (skip for WASM and cross-compilation)
    // Dynamic libraries can only be built for the host platform reliably
    const is_native_target = target.query.isNative();
    if (is_native_compatible and is_native_target) {
        const ffi_shared_lib = b.addLibrary(.{
            .name = "liquidz_ffi",
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/ffi.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "liquidz", .module = liquidz_mod },
                },
            }),
        });
        ffi_shared_lib.linkLibC();
        b.installArtifact(ffi_shared_lib);
    }

    // Run step
    if (exe) |exe_val| {
        const run_cmd = b.addRunArtifact(exe_val);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // Benchmark executable (skip for WASM and Apple embedded platforms)
    if (is_native_compatible and !is_apple_embedded) {
        const bench_exe = b.addExecutable(.{
            .name = "bench",
            .root_module = b.createModule(.{
                .root_source_file = b.path("benchmark/bench.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "liquidz", .module = liquidz_mod },
                },
            }),
        });
        b.installArtifact(bench_exe);

        const bench_step = b.step("bench", "Build benchmark tool");
        bench_step.dependOn(&b.addInstallArtifact(bench_exe, .{}).step);
    }

    // Unit tests for lib
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Unit tests for exe
    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "liquidz", .module = liquidz_mod },
            },
        }),
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    // WebAssembly build - produces a .wasm file with exported functions for browser use
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm_exe = b.addExecutable(.{
        .name = "liquidz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm_ffi.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "liquidz", .module = liquidz_mod },
            },
        }),
    });
    // Export all public functions and don't require entry point
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;

    const wasm_step = b.step("wasm", "Build WebAssembly module for browser");
    wasm_step.dependOn(&b.addInstallArtifact(wasm_exe, .{}).step);
}
