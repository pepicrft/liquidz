require "liquid"
require "liquidz_ext"

module Liquidz
  class Template
    def initialize(source)
      @source = source
    end

    def render(context = {}, **_opts)
      Liquidz.render(@source, context)
    end

    def render!(*args, **kwargs)
      render(*args, **kwargs)
    end
  end

  def self.enable_liquid_patch!
    return if @liquid_patch_enabled

    Liquid::Template.singleton_class.class_eval do
      unless method_defined?(:liquidz_orig_parse)
        alias_method :liquidz_orig_parse, :parse
      end

      def parse(source, *args, **_kwargs)
        Liquidz::Template.new(source)
      end
    end

    @liquid_patch_enabled = true
  end
end

Liquidz.enable_liquid_patch!
