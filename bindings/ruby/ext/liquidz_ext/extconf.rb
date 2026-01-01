require "mkmf"

# Find the Zig-built library (bindings/ruby -> zig-out/lib)
project_root = File.expand_path("../../../..", __dir__)
lib_dir = File.join(project_root, "zig-out", "lib")

# Link against the static library directly
$LDFLAGS << " #{File.join(lib_dir, 'libliquidz_ffi.a')}"

create_makefile("liquidz_ext/liquidz_ext")
