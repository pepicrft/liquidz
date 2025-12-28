require "mkmf"

project_root = File.expand_path("../..", __dir__)
lib_dir = File.join(project_root, "zig-out", "lib")

dir_config("liquidz_ext", nil, lib_dir)
have_library("liquidz_ffi")

create_makefile("liquidz_ext/liquidz_ext")
