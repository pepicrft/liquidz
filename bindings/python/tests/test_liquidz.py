"""Tests for the Liquidz Python binding."""

import pytest
from liquidz import render, render_string, RenderError


def test_simple_variable():
    result = render("Hello, {{ name }}!", {"name": "World"})
    assert result == "Hello, World!"


def test_loop():
    result = render("{% for item in items %}{{ item }} {% endfor %}", {"items": ["a", "b", "c"]})
    assert result == "a b c "


def test_conditional():
    result = render("{% if show %}visible{% else %}hidden{% endif %}", {"show": True})
    assert result == "visible"


def test_filter():
    result = render("{{ name | upcase }}", {"name": "hello"})
    assert result == "HELLO"


def test_json_string_data():
    result = render("{{ x }}", '{"x": 42}')
    assert result == "42"


def test_empty_data():
    result = render("Hello")
    assert result == "Hello"


def test_none_data():
    result = render("Hello", None)
    assert result == "Hello"


def test_nested_objects():
    result = render("{{ user.name }}", {"user": {"name": "Alice"}})
    assert result == "Alice"


def test_render_string_alias():
    result = render_string("Hello, {{ name }}!", {"name": "World"})
    assert result == "Hello, World!"


def test_array_filters():
    result = render("{{ items | join: ', ' }}", {"items": ["a", "b", "c"]})
    assert result == "a, b, c"


def test_math_filters():
    result = render("{{ 5 | plus: 3 }}")
    assert result == "8"


def test_multiple_variables():
    result = render("{{ first }} {{ last }}", {"first": "John", "last": "Doe"})
    assert result == "John Doe"


def test_unless_tag():
    result = render("{% unless hide %}visible{% endunless %}", {"hide": False})
    assert result == "visible"


def test_assign_tag():
    result = render("{% assign x = 5 %}{{ x }}")
    assert result == "5"


def test_capture_tag():
    result = render("{% capture greeting %}Hello{% endcapture %}{{ greeting }}, World!")
    assert result == "Hello, World!"
