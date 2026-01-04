#!/usr/bin/env ruby
# frozen_string_literal: true

# Liquid Spec Test Runner for Liquidz
#
# This script runs the liquid-spec test suite (https://github.com/Shopify/liquid-spec)
# against the liquidz binary and reports the results.
#
# Updated for the new liquid-spec format that uses `instantiate:ClassName`
# instead of Ruby YAML tags like `!ruby/object`.

require 'yaml'
require 'json'
require 'open3'
require 'optparse'
require 'bigdecimal'
require 'date'
require 'set'

# =============================================================================
# Object Instantiation Registry
# =============================================================================
# Maps class names to lambdas that create instances with the given params.
# This mirrors liquid-spec's ClassRegistry approach.

INSTANTIATE_REGISTRY = {
  # Ranges - params is an array [start, end]
  'Range' => ->(params) {
    return nil unless params.is_a?(Array) && params.length == 2
    { '_liquidz_range' => true, 'start' => params[0], 'end' => params[1] }
  },

  # Value drops - params has a 'value' key
  'ThingWithValue' => ->(params) {
    value = params.is_a?(Hash) ? (params['value'] || 3) : 3
    value
  },

  'ThingWithToLiquid' => ->(_params) {
    'foobar'
  },

  'NumberLikeThing' => ->(params) {
    params.is_a?(Hash) ? params['value'] : params
  },

  'IntegerDrop' => ->(params) {
    value = params.is_a?(Hash) ? params['value'] : params
    value.to_i
  },

  'StringDrop' => ->(params) {
    value = params.is_a?(Hash) ? params['value'] : params
    value.to_s
  },

  'BooleanDrop' => ->(params) {
    value = params.is_a?(Hash) ? params['value'] : params
    {
      '_liquidz_boolean_drop' => true,
      'truthy' => value,
      'display' => value ? 'Yay' : 'Nay'
    }
  },

  # Test objects
  'TestThing' => ->(_params) {
    { '_liquidz_custom_to_s' => 'woot: 1', 'whatever' => 'woot: 1' }
  },

  'TestEnumerable' => ->(_params) {
    [{ 'foo' => 1, 'bar' => 2 }, { 'foo' => 2, 'bar' => 1 }, { 'foo' => 3, 'bar' => 3 }]
  },

  'ErrorDrop' => ->(_params) {
    { '_liquidz_error_drop' => true }
  },

  # Loader drop - has data array for iteration
  'LoaderDrop' => ->(params) {
    params.is_a?(Hash) ? (params['data'] || []) : []
  },

  # Array drop - wraps an array
  'ArrayDrop' => ->(params) {
    params.is_a?(Hash) ? (params['array'] || []) : (params.is_a?(Array) ? params : [])
  },

  # Hash variants
  'HashWithCustomToS' => ->(params) {
    result = params.is_a?(Hash) ? params.dup : {}
    result['_liquidz_custom_to_s'] = 'kewl'
    result
  },

  'HashWithoutCustomToS' => ->(params) {
    params.is_a?(Hash) ? params.dup : {}
  },

  # Template factory stub
  'StubTemplateFactory' => ->(_params) {
    { '_liquidz_template_factory' => true }
  },

  # File system stub
  'StubFileSystem' => ->(params) {
    params.is_a?(Hash) ? params : {}
  },
}

# =============================================================================
# Instantiate Format Parser
# =============================================================================
# Recursively processes a data structure, looking for the `instantiate:ClassName`
# pattern and converting it to appropriate JSON-compatible values.

def process_instantiate_format(obj, visited = Set.new)
  # Prevent infinite recursion with object identity
  obj_id = obj.object_id
  if (obj.is_a?(Hash) || obj.is_a?(Array)) && visited.include?(obj_id)
    return obj.is_a?(Hash) ? {} : []
  end
  visited = visited.dup
  visited.add(obj_id) if obj.is_a?(Hash) || obj.is_a?(Array)

  case obj
  when Hash
    # Check if this hash has an instantiate key
    instantiate_key = obj.keys.find { |k| k.to_s.start_with?('instantiate:') }

    if instantiate_key
      # Format: { "instantiate:ClassName": params } or { "instantiate:ClassName": {} }
      class_name = instantiate_key.to_s.sub('instantiate:', '')
      params = process_instantiate_format(obj[instantiate_key], visited)
      return create_instance(class_name, params)
    end

    # Check for "instantiate" as a value key (nested format)
    if obj.key?('instantiate')
      class_name = obj['instantiate']
      params = obj.reject { |k, _| k == 'instantiate' }
      params = process_instantiate_format(params, visited)
      return create_instance(class_name, params)
    end

    # Regular hash - process all values recursively
    result = {}
    obj.each do |k, v|
      # Handle special key formats
      if k.is_a?(Symbol)
        result[':' + k.to_s] = process_instantiate_format(v, visited)
        result['_liquidz_has_symbol_keys'] = true
      else
        result[k.to_s] = process_instantiate_format(v, visited)
      end
    end
    result

  when Array
    obj.map { |v| process_instantiate_format(v, visited) }

  when String
    # Check for inline instantiate format: "instantiate:ClassName"
    if obj.start_with?('instantiate:')
      class_name = obj.sub('instantiate:', '')
      return create_instance(class_name, {})
    end
    obj

  else
    obj
  end
end

def create_instance(class_name, params)
  factory = INSTANTIATE_REGISTRY[class_name]
  if factory
    factory.call(params)
  else
    # Unknown class - skip this value or return raw params
    puts "Warning: Unknown instantiate class: #{class_name}" if ENV['LIQUIDZ_DEBUG']
    params
  end
end

# =============================================================================
# JSON Conversion for Complex Ruby Types
# =============================================================================
# Handles remaining Ruby types that might appear in specs.

def convert_to_json_compatible(obj, visited = Set.new)
  return obj if obj.nil?

  # Prevent infinite recursion
  obj_id = obj.object_id
  return nil if visited.include?(obj_id) && obj.is_a?(Hash)
  visited = visited.dup
  visited.add(obj_id) if obj.is_a?(Hash) || obj.is_a?(Array)

  case obj
  when Hash
    result = {}
    obj.each do |k, v|
      converted = convert_to_json_compatible(v, visited)
      next if converted.nil? && !v.nil?

      if k.is_a?(Symbol)
        result[':' + k.to_s] = converted
        result['_liquidz_has_symbol_keys'] = true
      else
        result[k.to_s] = converted
      end
    end
    result

  when Array
    obj.map { |v| convert_to_json_compatible(v, visited) }.compact

  when Range
    { '_liquidz_range' => true, 'start' => obj.begin, 'end' => obj.end }

  when Symbol
    { '_liquidz_symbol' => true, 'name' => obj.to_s }

  when String, Integer, Float, TrueClass, FalseClass
    obj

  when Time, Date, DateTime
    obj.to_s

  when BigDecimal
    obj.to_f

  else
    if obj.respond_to?(:to_liquid)
      convert_to_json_compatible(obj.to_liquid, visited)
    elsif obj.respond_to?(:to_h)
      convert_to_json_compatible(obj.to_h, visited)
    elsif obj.respond_to?(:to_a)
      convert_to_json_compatible(obj.to_a, visited)
    else
      nil
    end
  end
end

# =============================================================================
# Test Runner
# =============================================================================

class LiquidSpecTestRunner
  # Test name patterns that require Ruby-specific features we can't support
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
    @suite = options[:suite]
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
      # Use safe_load - the new format doesn't require Ruby objects
      specs = YAML.safe_load_file(spec_file, permitted_classes: [Symbol, Date, Time, Range], aliases: true)
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

    # Process the instantiate format and convert to JSON-compatible
    processed_env = process_instantiate_format(environment)
    json_env = convert_to_json_compatible(processed_env)
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

# =============================================================================
# CLI
# =============================================================================

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

  opts.on('--suite SUITE', 'Run a specific suite (liquid_ruby, basics, etc.)') do |suite|
    options[:suite] = suite
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
spec_base_dir = File.join(script_dir, 'liquid-spec', 'specs')

unless File.exist?(liquidz_binary)
  puts "Error: liquidz binary not found at #{liquidz_binary}"
  puts "Please build the project first with: zig build"
  exit 1
end

# Determine which spec files to run
if options[:spec_file]
  spec_files = [options[:spec_file]]
elsif options[:suite]
  suite_dir = File.join(spec_base_dir, options[:suite])
  if File.directory?(suite_dir)
    spec_files = Dir.glob(File.join(suite_dir, '*.yml')).sort
  else
    puts "Error: Suite '#{options[:suite]}' not found in #{spec_base_dir}"
    exit 1
  end
else
  # Default to liquid_ruby suite for backwards compatibility
  spec_dir = File.join(spec_base_dir, 'liquid_ruby')
  spec_files = Dir.glob(File.join(spec_dir, '*.yml')).sort
end

if spec_files.empty?
  puts "Error: No spec files found"
  exit 1
end

runner = LiquidSpecTestRunner.new(liquidz_binary, spec_files, options)
success = runner.run

exit(success ? 0 : 1)
