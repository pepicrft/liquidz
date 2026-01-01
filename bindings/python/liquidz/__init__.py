"""
Liquidz - High-performance Liquid template engine powered by Zig.

Example usage:
    >>> from liquidz import render
    >>> render("Hello, {{ name }}!", {"name": "World"})
    'Hello, World!'
"""

from .core import render, render_string, LiquidzError, RenderError

__version__ = "0.2.0"
__all__ = ["render", "render_string", "LiquidzError", "RenderError", "__version__"]
