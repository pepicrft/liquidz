defmodule LiquidzTest do
  use ExUnit.Case
  doctest Liquidz

  test "simple variable" do
    assert Liquidz.render!("Hello, {{ name }}!", %{name: "World"}) == "Hello, World!"
  end

  test "loop" do
    result = Liquidz.render!("{% for item in items %}{{ item }} {% endfor %}", %{items: ["a", "b", "c"]})
    assert result == "a b c "
  end

  test "conditional" do
    assert Liquidz.render!("{% if show %}visible{% else %}hidden{% endif %}", %{show: true}) == "visible"
  end

  test "filter" do
    assert Liquidz.render!("{{ name | upcase }}", %{name: "hello"}) == "HELLO"
  end

  test "JSON string data" do
    assert Liquidz.render!("{{ x }}", ~s({"x": 42})) == "42"
  end

  test "empty data" do
    assert Liquidz.render!("Hello") == "Hello"
  end

  test "nested objects" do
    assert Liquidz.render!("{{ user.name }}", %{user: %{name: "Alice"}}) == "Alice"
  end

  test "keyword list data" do
    assert Liquidz.render!("{{ name }}", name: "World") == "World"
  end

  test "render returns tuple" do
    assert {:ok, "Hello, World!"} = Liquidz.render("Hello, {{ name }}!", %{name: "World"})
  end
end
