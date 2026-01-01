{
  "targets": [
    {
      "target_name": "liquidz",
      "sources": ["src/liquidz.c"],
      "include_dirs": [],
      "libraries": [
        "<(module_root_dir)/../../zig-out/lib/libliquidz_ffi.a"
      ],
      "cflags": ["-Wall", "-Wextra"],
      "xcode_settings": {
        "OTHER_LDFLAGS": [
          "<(module_root_dir)/../../zig-out/lib/libliquidz_ffi.a"
        ]
      },
      "conditions": [
        ["OS=='linux'", {
          "libraries": ["-lm", "-lpthread"]
        }],
        ["OS=='mac'", {
          "libraries": ["-lm"]
        }]
      ]
    }
  ]
}
