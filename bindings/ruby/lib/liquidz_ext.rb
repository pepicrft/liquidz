require "json"
require "liquidz_ext/liquidz_ext"

# Liquidz - High-performance Liquid template engine powered by Zig
#
# @example Basic usage
#   Liquidz.render("Hello, {{ name }}!", { name: "World" })
#   # => "Hello, World!"
#
# @example With loops
#   Liquidz.render("{% for item in items %}{{ item }} {% endfor %}", { items: ["a", "b", "c"] })
#   # => "a b c "
#
# @example With filters
#   Liquidz.render("{{ name | upcase }}", { name: "hello" })
#   # => "HELLO"
#
module Liquidz
  class Error < StandardError; end
  class RenderError < Error; end

  # Renders a Liquid template with the given data.
  #
  # @param template [String] The Liquid template string
  # @param data [Hash, String, nil] The data to render with (Hash or JSON string)
  # @return [String] The rendered template
  # @raise [RenderError] If rendering fails
  #
  # @example
  #   Liquidz.render_string("Hello, {{ name }}!", { name: "World" })
  #   # => "Hello, World!"
  #
  def self.render_string(template, data = nil)
    render(template, data)
  rescue => e
    raise RenderError, "Failed to render template: #{e.message}"
  end

  # Returns the version of the Liquidz library.
  #
  # @return [String] The version string
  #
  def self.version
    "0.2.0"
  end
end
