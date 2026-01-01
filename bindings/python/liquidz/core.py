"""
Core functionality for the Liquidz Python binding.
"""

import ctypes
import json
import os
import platform
from pathlib import Path
from typing import Any, Dict, Optional, Union


class LiquidzError(Exception):
    """Base exception for Liquidz errors."""
    pass


class RenderError(LiquidzError):
    """Exception raised when template rendering fails."""
    pass


def _find_library() -> Path:
    """Find the liquidz_ffi library in common locations."""
    system = platform.system()
    machine = platform.machine().lower()

    if system == "Darwin":
        dylib_name = "libliquidz_ffi.dylib"
    elif system == "Windows":
        dylib_name = "liquidz_ffi.dll"
    else:  # Linux and others
        dylib_name = "libliquidz_ffi.so"

    # Search paths (prefer dynamic library for ctypes)
    search_paths = [
        # Bundled with package (installed via pip)
        Path(__file__).parent / "lib",
        # Relative to this module (development)
        Path(__file__).parent.parent.parent.parent / "zig-out" / "lib",
        # System paths
        Path("/usr/local/lib"),
        Path("/usr/lib"),
    ]

    # First try dynamic library
    for search_path in search_paths:
        dylib_path = search_path / dylib_name
        if dylib_path.exists():
            return dylib_path

    # Fallback message
    raise LiquidzError(
        f"Could not find liquidz library ({dylib_name}). "
        f"System: {system}, Machine: {machine}. "
        "Make sure to install the correct platform-specific package."
    )


def _get_library():
    """Load and return the liquidz FFI library."""
    lib_path = _find_library()
    lib = ctypes.CDLL(str(lib_path))

    # Define function signatures
    lib.liquidz_render_json.argtypes = [
        ctypes.c_char_p,  # template_ptr
        ctypes.c_size_t,  # template_len
        ctypes.c_char_p,  # json_ptr
        ctypes.c_size_t,  # json_len
        ctypes.POINTER(ctypes.c_char_p),  # out_ptr
        ctypes.POINTER(ctypes.c_size_t),  # out_len
    ]
    lib.liquidz_render_json.restype = ctypes.c_int

    lib.liquidz_free.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    lib.liquidz_free.restype = None

    return lib


# Lazy load the library
_lib: Optional[ctypes.CDLL] = None


def _ensure_library():
    """Ensure the library is loaded."""
    global _lib
    if _lib is None:
        _lib = _get_library()
    return _lib


def render(
    template: str,
    data: Optional[Union[Dict[str, Any], str]] = None
) -> str:
    """
    Render a Liquid template with the given data.

    Args:
        template: The Liquid template string.
        data: The data to render with. Can be a dict or a JSON string.
              Defaults to an empty dict.

    Returns:
        The rendered template as a string.

    Raises:
        RenderError: If rendering fails.
        LiquidzError: If the library cannot be loaded.

    Examples:
        >>> render("Hello, {{ name }}!", {"name": "World"})
        'Hello, World!'

        >>> render("{% for item in items %}{{ item }} {% endfor %}", {"items": ["a", "b", "c"]})
        'a b c '

        >>> render("{{ name | upcase }}", {"name": "hello"})
        'HELLO'
    """
    lib = _ensure_library()

    # Encode template
    template_bytes = template.encode("utf-8")

    # Encode data as JSON
    if data is None:
        json_str = "{}"
    elif isinstance(data, str):
        json_str = data
    else:
        json_str = json.dumps(data)
    json_bytes = json_str.encode("utf-8")

    # Prepare output pointers
    out_ptr = ctypes.c_char_p()
    out_len = ctypes.c_size_t()

    # Call the FFI function
    result = lib.liquidz_render_json(
        template_bytes,
        len(template_bytes),
        json_bytes,
        len(json_bytes),
        ctypes.byref(out_ptr),
        ctypes.byref(out_len),
    )

    if result != 0:
        raise RenderError("Failed to render Liquid template")

    # Copy the result and free the memory
    output = ctypes.string_at(out_ptr, out_len.value).decode("utf-8")
    lib.liquidz_free(out_ptr, out_len)

    return output


def render_string(
    template: str,
    data: Optional[Union[Dict[str, Any], str]] = None
) -> str:
    """
    Render a Liquid template with the given data (alias for render).

    Args:
        template: The Liquid template string.
        data: The data to render with. Can be a dict or a JSON string.
              Defaults to an empty dict.

    Returns:
        The rendered template as a string.

    Raises:
        RenderError: If rendering fails.
    """
    return render(template, data)
