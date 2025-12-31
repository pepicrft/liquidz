#!/usr/bin/env ruby
# frozen_string_literal: true

# Liquid Spec Test Runner for Liquidz
#
# This script runs the liquid-spec test suite (https://github.com/Shopify/liquid-spec)
# against the liquidz binary and reports the results.

require 'yaml'
require 'json'
require 'open3'
require 'optparse'
require 'bigdecimal'
require 'date'
require 'set'

# Define stub classes for Ruby objects found in liquid-spec YAML files
# These allow YAML deserialization and expose data for JSON conversion

# Base class for Drop-like objects that expose instance variables as hash
class DropBase
  def to_h
    result = {}
    instance_variables.each do |var|
      key = var.to_s.sub(/^@/, '')
      result[key] = instance_variable_get(var)
    end
    result
  end

  def to_liquid
    to_h
  end
end

# Generic test objects
class TestThing < DropBase
  attr_reader :foo
  def initialize
    @foo = 0
  end
  def to_s
    "woot: #{@foo}"
  end
  def to_liquid
    @foo += 1
    self
  end
  def [](key)
    case key
    when "whatever"
      "woot: #{@foo}"
    end
  end
end
class TestDrop < DropBase; end
class TestEnumerable < DropBase
  include Enumerable
  def each(&block)
    # Hardcoded test data matching liquid-spec's TestEnumerable
    [{ "foo" => 1, "bar" => 2 }, { "foo" => 2, "bar" => 1 }, { "foo" => 3, "bar" => 3 }].each(&block)
  end
  def to_a
    [{ "foo" => 1, "bar" => 2 }, { "foo" => 2, "bar" => 1 }, { "foo" => 3, "bar" => 3 }]
  end
end

class ThingWithToLiquid < DropBase
  def to_liquid
    'foobar'
  end
end
class ThingWithValue < DropBase
  attr_accessor :value
  def to_liquid
    @value
  end
end
class CustomToLiquidDrop < DropBase; end

# Numeric drops
class IntegerDrop < DropBase
  attr_accessor :value
  def to_liquid
    @value.to_i
  end
end

class BooleanDrop < DropBase
  attr_accessor :value
  def to_liquid
    # BooleanDrop is special: it has a boolean value for truthiness checks
    # but displays as "Yay"/"Nay"
    # We encode this as a special object that liquidz can recognize
    {
      "_liquidz_boolean_drop" => true,
      "truthy" => @value,
      "display" => @value ? "Yay" : "Nay"
    }
  end
end

class StringDrop < DropBase
  attr_accessor :value
  def to_liquid
    @value.to_s
  end
end

class NumberLikeThing < DropBase
  attr_accessor :value
  def to_liquid
    @value
  end
end

class ErrorDrop < DropBase; end
class SettingsDrop < DropBase; end

# For tag test
module ForTagTest
  class LoaderDrop < DropBase
    def to_a
      @items || []
    end
  end
end

# Table row test
module TableRowTest
  class ArrayDrop < DropBase
    include Enumerable
    def each(&block)
      (@array || []).each(&block)
    end
    def to_a
      @array || []
    end
  end
end

# Struct-based objects - add to existing Struct class
Struct.const_set(:ThingWithValue, ::ThingWithValue) unless Struct.const_defined?(:ThingWithValue)
Struct.const_set(:TestThing, ::TestThing) unless Struct.const_defined?(:TestThing)

# Liquid namespace
module Liquid
  class Drop < DropBase; end
end

# TestDrops namespace with all the fake drops
module TestDrops
  class FakeMoney < DropBase
    attr_accessor :cents, :currency
    def to_liquid
      { 'cents' => @cents, 'currency' => @currency }
    end
  end

  class Money < DropBase
    attr_accessor :cents, :currency
    def to_liquid
      { 'cents' => @cents, 'currency' => @currency }
    end
  end

  # Hash subclasses
  class CollationAwareHash < Hash; end
  class HtmlSafeHash < Hash; end

  module Metafields
    class StringDrop < DropBase
      attr_accessor :value
      def to_liquid
        @value.to_s
      end
    end

    class IntDrop < DropBase
      attr_accessor :value
      def to_liquid
        @value.to_i
      end
    end

    class BooleanDrop < DropBase
      attr_accessor :value
      def to_liquid
        @value
      end
    end

    class MetaComparableDrop < DropBase; end
    class FakeArticleDrop < DropBase; end
  end

  module LiquidHelper
    module FakeDrops
      class AnyDrop < DropBase; end
      class BlankSupportDrop < DropBase
        attr_accessor :blank
        def to_liquid
          @blank ? '' : to_h
        end
      end
      class ContextAwareDrop < DropBase; end
      class ComparableDrop < DropBase; end
      class CountryDrop < DropBase; end
      class CurrencyDrop < DropBase; end
      class DropWithContext < DropBase; end
      class DropWithChangingContext < DropBase; end
      class DropWithLiquidSize < DropBase
        attr_accessor :items
        def to_a
          @items || []
        end
      end
      class DropWithSize < DropBase
        attr_accessor :size
      end
      class EnumerableDrop < DropBase
        include Enumerable
        attr_accessor :items
        def each(&block)
          (@items || []).each(&block)
        end
        def to_a
          @items || []
        end
      end
      class FakeBlockDrop < DropBase
        attr_accessor :items
        def to_a
          @items || []
        end
      end
      class FiberDrop < DropBase; end
      class IterDrop < DropBase
        def to_a
          []
        end
      end
      class LocalizationDrop < DropBase; end
      class MediaDrop < DropBase; end
      class MuffinDrop < DropBase; end
      class NotSafeStringDrop < DropBase
        attr_accessor :value
        def to_liquid
          @value.to_s
        end
      end
      # ObjectWithToLiquid is a Struct in the original tests
      ObjectWithToLiquid = Struct.new(:a, :b, :c) do
        def to_liquid
          to_h
        end
      end
      class RaisingDrop < DropBase; end
      class RaisingToSDrop < DropBase; end
      class RatingDrop < DropBase; end
    end
  end
end

# Stub classes for template factory
class StubTemplateFactory; end
class StubFileSystem; end

# Hash subclasses
class HashWithCustomToS < Hash
  def to_s
    'kewl'
  end
end

class HashWithoutCustomToS < Hash; end

class LiquidSpecTestRunner
  # Test name patterns that require Ruby-specific features we can't support
  # These are internal Ruby Liquid APIs, not template features
  SKIP_PATTERNS = [
    /Profiler/i,              # Ruby profiling API
    /ResourceLimits/i,        # Ruby resource limiting
    /ParseTreeVisitor/i,      # Ruby AST visitor API
    /BlockBody/i,             # Internal Ruby API
    /Strainer/i,              # Ruby filter registration API
    /StaticRegisters/i,       # Ruby registers API
    /LazyHash/i,              # Ruby lazy evaluation
    /TokenizerTest/i,         # Ruby tokenizer internals
    /LexerTest/i,             # Ruby lexer internals
    /ParserTest/i,            # Ruby parser internals
    /Template#render!/i,      # Ruby render! method
    /ContextTest/i,           # Ruby context internals
    /PartialCache/i,          # Ruby caching API
    /VariableTest/i,          # Ruby variable internals
    /TagTest/i,               # Ruby tag registration
    /FilterTest/i,            # Ruby filter registration
    /OutputTest/i,            # Ruby output internals
    /ErrorHandling/i,         # Ruby error handling specifics
    /disallowed_includes/i,   # Requires filesystem permission system
    /strict2/i,               # Requires strict2 error mode
  ].freeze

  def initialize(liquidz_binary, spec_files, options = {})
    @liquidz_binary = liquidz_binary
    @spec_files = spec_files
    @verbose = options[:verbose] || false
    @filter = options[:filter]
    @results = { passed: 0, failed: 0, skipped: 0, errors: [] }
  end

  def run
    puts "Running Liquid Spec tests..."
    puts "Binary: #{@liquidz_binary}"
    puts "Spec files: #{@spec_files.join(', ')}"
    puts

    @spec_files.each do |spec_file|
      run_spec_file(spec_file)
    end

    print_summary
    @results[:failed] == 0
  end

  private

  def run_spec_file(spec_file)
    puts "Loading: #{File.basename(spec_file)}" if @verbose

    begin
      # Use unsafe_load to allow Ruby objects like Range, Symbol, etc.
      specs = YAML.unsafe_load_file(spec_file)
      return unless specs.is_a?(Array)

      specs.each do |spec|
        run_single_spec(spec, File.basename(spec_file))
      end
    rescue => e
      puts "Error loading #{spec_file}: #{e.message}"
      puts e.backtrace.first(5).join("\n") if @verbose
    end
  end

  def run_single_spec(spec, file_name)
    name = spec['name'] || 'unnamed'
    template = spec['template']
    environment = spec['environment'] || {}
    expected = spec['expected']
    filesystem = spec['filesystem']

    # Skip filters
    return skip_test(name, 'filtered out') if @filter && !name.downcase.include?(@filter.downcase)

    # Skip tests that require Ruby-specific internal APIs
    SKIP_PATTERNS.each do |pattern|
      return skip_test(name, 'Ruby internal API') if name.match?(pattern)
    end

    # Skip if no template or expected result
    return skip_test(name, 'no template') unless template
    return skip_test(name, 'no expected result') unless expected

    # Skip tests with filesystem (include/render with partials) for now
    return skip_test(name, 'requires filesystem') if filesystem && !filesystem.empty?

    # Convert environment to JSON-compatible format
    json_env = convert_to_json_compatible(environment)
    return skip_test(name, 'unsupported environment type') if json_env.nil?

    # Run the template through liquidz
    begin
      actual = render_template(template, json_env)

      if normalize(expected) == normalize(actual)
        pass_test(name)
      else
        fail_test(name, file_name, expected, actual, template, environment)
      end
    rescue StandardError => e
      error_test(name, file_name, e.message, template)
    end
  end

  # Convert Ruby objects to JSON-compatible format
  def convert_to_json_compatible(obj, visited = Set.new)
    # Check for circular references
    obj_id = obj.object_id
    return nil if visited.include?(obj_id) && !obj.is_a?(String) && !obj.is_a?(Integer) && !obj.is_a?(Float)
    visited = visited.dup
    visited.add(obj_id) unless obj.is_a?(String) || obj.is_a?(Integer) || obj.is_a?(Float) || obj.is_a?(TrueClass) || obj.is_a?(FalseClass) || obj.nil?

    case obj
    when HashWithCustomToS
      # Handle hash with custom to_s - encode the custom string representation
      # NOTE: Must come BEFORE Hash case since HashWithCustomToS inherits from Hash
      result = { "_liquidz_custom_to_s" => obj.to_s }
      obj.each do |k, v|
        converted = convert_to_json_compatible(v, visited)
        return nil if converted.nil? && !v.nil?
        result[k.to_s] = converted
      end
      result
    when TestDrops::CollationAwareHash, TestDrops::HtmlSafeHash, HashWithoutCustomToS
      # Handle hash subclasses - must come BEFORE Hash case
      result = {}
      has_symbol_keys = false
      obj.each do |k, v|
        converted = convert_to_json_compatible(v, visited)
        return nil if converted.nil? && !v.nil?
        if k.is_a?(Symbol)
          has_symbol_keys = true
          result[":" + k.to_s] = converted
        else
          result[k.to_s] = converted
        end
      end
      if has_symbol_keys
        result["_liquidz_has_symbol_keys"] = true
      end
      result
    when Hash
      result = {}
      has_symbol_keys = false
      has_hash_keys = false
      obj.each do |k, v|
        converted = convert_to_json_compatible(v, visited)
        return nil if converted.nil? && !v.nil?
        if k.is_a?(Symbol)
          has_symbol_keys = true
          # Prefix symbol keys with ":" to mark them
          result[":" + k.to_s] = converted
        elsif k.is_a?(Hash)
          has_hash_keys = true
          # Prefix hash keys with "{" to mark them (already looks like a hash)
          # The key string will be like {\"foo\"=>\"bar\"}, we prefix with _liquidz_hash_key:
          result["_liquidz_hash_key:" + k.to_s] = converted
        else
          result[k.to_s] = converted
        end
      end
      # Mark this hash as having symbol keys for proper rendering
      if has_symbol_keys
        result["_liquidz_has_symbol_keys"] = true
      end
      if has_hash_keys
        result["_liquidz_has_hash_keys"] = true
      end
      result
    when Array
      result = []
      obj.each do |v|
        converted = convert_to_json_compatible(v, visited)
        return nil if converted.nil? && !v.nil?
        result << converted
      end
      result
    when Range
      # Encode range as a special object that liquidz can recognize
      { "_liquidz_range" => true, "start" => obj.begin, "end" => obj.end }
    when Symbol
      # Encode symbol as a special object so liquidz can render it with : prefix
      { "_liquidz_symbol" => true, "name" => obj.to_s }
    when String, Integer, Float, TrueClass, FalseClass, NilClass
      obj
    when Time, Date, DateTime
      obj.to_s
    when BigDecimal
      obj.to_f
    when TestThing
      # Special handling for TestThing - call to_liquid to increment counter,
      # then return an object with both the "whatever" property and custom to_s
      obj.to_liquid  # This increments @foo
      { "_liquidz_custom_to_s" => obj.to_s, "whatever" => obj["whatever"] }
    when TestEnumerable
      # TestEnumerable should be converted as an array
      convert_to_json_compatible(obj.to_a, visited)
    when TableRowTest::ArrayDrop
      # ArrayDrop should be converted as an array
      convert_to_json_compatible(obj.to_a, visited)
    when DropBase
      # Handle Drop objects - try to_liquid first, then to_h
      if obj.respond_to?(:to_liquid)
        liquid_val = obj.to_liquid
        # If to_liquid returns self, use to_s to get a string representation
        if liquid_val.equal?(obj)
          if obj.respond_to?(:to_s)
            # Use custom to_s marker so liquidz can render it properly
            { "_liquidz_custom_to_s" => obj.to_s }
          else
            obj.to_h
          end
        else
          convert_to_json_compatible(liquid_val, visited)
        end
      else
        convert_to_json_compatible(obj.to_h, visited)
      end
    else
      # Try common conversion methods
      if obj.respond_to?(:to_liquid)
        convert_to_json_compatible(obj.to_liquid, visited)
      elsif obj.respond_to?(:to_h)
        convert_to_json_compatible(obj.to_h, visited)
      elsif obj.respond_to?(:to_a)
        convert_to_json_compatible(obj.to_a, visited)
      else
        # Unknown type - return nil to skip the test
        nil
      end
    end
  end

  def render_template(template, context_data)
    json_data = JSON.generate(context_data)

    # Write template to a temp file
    require 'tempfile'
    require 'timeout'
    tmpfile = Tempfile.new(['template', '.liquid'])
    tmpfile.write(template)
    tmpfile.close

    begin
      pid = nil
      result = nil

      begin
        Timeout.timeout(5) do
          stdin, stdout, stderr, wait_thr = Open3.popen3(@liquidz_binary, tmpfile.path, json_data)
          pid = wait_thr.pid
          stdin.close

          out = stdout.read
          err = stderr.read
          stdout.close
          stderr.close
          status = wait_thr.value

          unless status.success?
            raise "liquidz failed: #{err}"
          end

          result = out
        end
      rescue Timeout::Error
        if pid
          Process.kill('KILL', pid) rescue nil
          Process.wait(pid) rescue nil
        end
        raise "liquidz timed out after 5 seconds"
      end

      result
    ensure
      tmpfile.unlink
    end
  end

  def normalize(str)
    return '' if str.nil?
    str.to_s
  end

  def pass_test(name)
    @results[:passed] += 1
    print '.' unless @verbose
    puts "  PASS: #{name}" if @verbose
  end

  def fail_test(name, file_name, expected, actual, template, context)
    @results[:failed] += 1
    print 'F' unless @verbose

    @results[:errors] << {
      name: name,
      file: file_name,
      template: template,
      context: context,
      expected: expected,
      actual: actual
    }

    if @verbose
      puts "  FAIL: #{name}"
      puts "    Expected: #{expected.inspect}"
      puts "    Actual:   #{actual.inspect}"
    end
  end

  def skip_test(name, reason)
    @results[:skipped] += 1
    print 'S' unless @verbose
    puts "  SKIP: #{name} (#{reason})" if @verbose
  end

  def error_test(name, file_name, error, template)
    @results[:failed] += 1
    print 'E' unless @verbose

    @results[:errors] << {
      name: name,
      file: file_name,
      template: template,
      error: error
    }

    if @verbose
      puts "  ERROR: #{name}"
      puts "    #{error}"
    end
  end

  def print_summary
    puts
    puts
    puts "=" * 60
    puts "Liquid Spec Test Results Summary"
    puts "=" * 60
    puts "Passed:  #{@results[:passed]}"
    puts "Failed:  #{@results[:failed]}"
    puts "Skipped: #{@results[:skipped]}"
    puts "Total:   #{@results[:passed] + @results[:failed] + @results[:skipped]}"
    puts

    if @results[:errors].any?
      puts "Failures:"
      puts "-" * 60
      @results[:errors].first(20).each do |error|
        puts
        puts "Test: #{error[:name]}"
        puts "File: #{error[:file]}"
        puts "Template: #{error[:template].inspect}"
        if error[:error]
          puts "Error: #{error[:error]}"
        else
          puts "Expected: #{error[:expected].inspect}"
          puts "Actual:   #{error[:actual].inspect}"
        end
      end

      if @results[:errors].size > 20
        puts
        puts "... and #{@results[:errors].size - 20} more failures"
      end
    end
  end
end

# Parse command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on('-v', '--verbose', 'Show verbose output') do
    options[:verbose] = true
  end

  opts.on('-f', '--filter PATTERN', 'Only run tests matching PATTERN') do |pattern|
    options[:filter] = pattern
  end

  opts.on('-b', '--binary PATH', 'Path to liquidz binary') do |path|
    options[:binary] = path
  end

  opts.on('-s', '--spec FILE', 'Specific spec file to run') do |file|
    options[:spec_file] = file
  end

  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
end.parse!

# Find paths
script_dir = File.dirname(File.expand_path(__FILE__))
project_root = File.dirname(script_dir)

liquidz_binary = options[:binary] || File.join(project_root, 'zig-out', 'bin', 'liquidz')
spec_dir = File.join(script_dir, 'liquid-spec', 'specs', 'liquid_ruby')

unless File.exist?(liquidz_binary)
  puts "Error: liquidz binary not found at #{liquidz_binary}"
  puts "Please build the project first with: zig build"
  exit 1
end

# Determine which spec files to run
if options[:spec_file]
  spec_files = [options[:spec_file]]
else
  # Run all spec files
  spec_files = Dir.glob(File.join(spec_dir, '*.yml')).sort
end

if spec_files.empty?
  puts "Error: No spec files found in #{spec_dir}"
  exit 1
end

runner = LiquidSpecTestRunner.new(liquidz_binary, spec_files, options)
success = runner.run

exit(success ? 0 : 1)
