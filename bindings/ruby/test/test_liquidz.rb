require "minitest/autorun"
require "liquidz_ext"

class TestLiquidz < Minitest::Test
  def test_simple_variable
    result = Liquidz.render("Hello, {{ name }}!", { name: "World" })
    assert_equal "Hello, World!", result
  end

  def test_loop
    result = Liquidz.render("{% for item in items %}{{ item }} {% endfor %}", { items: ["a", "b", "c"] })
    assert_equal "a b c ", result
  end

  def test_conditional
    result = Liquidz.render("{% if show %}visible{% else %}hidden{% endif %}", { show: true })
    assert_equal "visible", result
  end

  def test_filter
    result = Liquidz.render("{{ name | upcase }}", { name: "hello" })
    assert_equal "HELLO", result
  end

  def test_json_string_data
    result = Liquidz.render("{{ x }}", '{"x": 42}')
    assert_equal "42", result
  end

  def test_empty_data
    result = Liquidz.render("Hello", nil)
    assert_equal "Hello", result
  end

  def test_nested_objects
    result = Liquidz.render("{{ user.name }}", { user: { name: "Alice" } })
    assert_equal "Alice", result
  end

  def test_render_string_alias
    result = Liquidz.render_string("Hello, {{ name }}!", { name: "World" })
    assert_equal "Hello, World!", result
  end
end
