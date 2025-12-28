require "json"
require "liquidz_ext/liquidz_ext"

module Liquidz
  def self.render_string(template, data = nil)
    render(template, data)
  end
end
