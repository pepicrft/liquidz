#!/usr/bin/env ruby

require "pathname"

root = Pathname.new(__dir__).parent
shopify_dir = ENV["SHOPIFY_LIQUID_DIR"]

if shopify_dir.nil? || shopify_dir.empty?
  warn "Set SHOPIFY_LIQUID_DIR to a Shopify/liquid checkout"
  exit 1
end

lib_dir = root.join("lib").to_s
ext_dir = root.join("ext", "liquidz_ext").to_s

env = {
  "RUBYOPT" => "-I#{lib_dir} -I#{ext_dir} -rliquidz_ext -rliquidz_ext/liquid_patch",
}

Dir.chdir(shopify_dir) do
  exec(env, "bundle", "exec", "rake", "test")
end
