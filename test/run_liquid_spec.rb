#!/usr/bin/env ruby
# frozen_string_literal: true

# Test runner for Shopify's liquid-spec test suite
# https://github.com/Shopify/liquid-spec

require 'yaml'
require 'json'
require 'open3'
require 'fileutils'
require 'timeout'
require 'set'

BINARY_PATH = File.expand_path('../../zig-out/bin/liquidz', __FILE__)
SPEC_DIR = File.expand_path('../liquid-spec/specs/liquid_ruby', __FILE__)

class LiquidSpecRunner
  def initialize
    @passed = 0
    @failed = 0
    @skipped = 0
    @errors = 0
    @failures = []
  end

  def run
    puts "Running Shopify liquid-spec tests..."
    puts "Binary: #{BINARY_PATH}"
    puts "Spec directory: #{SPEC_DIR}"
    puts

    unless File.exist?(BINARY_PATH)
      puts "Error: liquidz binary not found. Run 'zig build -p zig-out' first."
      exit 1
    end

    # Load all YAML spec files
    spec_files = Dir.glob(File.join(SPEC_DIR, '*.yml'))

    spec_files.each do |spec_file|
      run_spec_file(spec_file)
    end

    print_summary
  end

  def run_spec_file(spec_file)
    # Skip files that contain Ruby-specific objects we can't serialize
    basename = File.basename(spec_file)
    return if basename == 'recorded_specs.yml'
    return if basename == 'specs.yml'  # Contains ThingWithValue, etc.

    begin
      specs = YAML.unsafe_load_file(spec_file)
    rescue => e
      puts "Failed to parse #{spec_file}: #{e.message}"
      return
    end
    return unless specs.is_a?(Array)

    specs.each do |spec|
      run_single_spec(spec, File.basename(spec_file))
    end
  end

  def run_single_spec(spec, source_file)
    name = spec['name']
    template = spec['template']
    expected = spec['expected']
    environment = spec['environment'] || {}
    filesystem = spec['filesystem'] || {}
    error_mode = spec['error_mode']
    render_errors = spec['render_errors']

    # Skip tests that require filesystem (include/render with external files)
    unless filesystem.empty?
      print 'S'
      @skipped += 1
      return
    end

    # Skip tests with :strict error mode that expect errors
    if error_mode == :strict && render_errors == false
      # These might be error cases, we'll try them
    end

    # Write template to temp file
    template_file = "/tmp/liquid_spec_template_#{$$}.liquid"
    File.write(template_file, template)

    # Convert environment to JSON (handle Ruby-specific types)
    begin
      serializable_env = make_json_serializable(environment)
      context_json = JSON.generate(serializable_env)
    rescue => e
      print 'S'
      @skipped += 1
      return
    end

    begin
      stdout, stderr, status = nil, nil, nil
      Timeout.timeout(5) do
        stdout, stderr, status = Open3.capture3(
          BINARY_PATH, template_file, context_json,
          stdin_data: ''
        )
      end

      actual = stdout

      if status.success?
        # Normalize line endings and trailing whitespace for comparison
        actual_normalized = actual.to_s
        expected_normalized = expected.to_s

        if actual_normalized == expected_normalized
          print '.'
          @passed += 1
        else
          print 'F'
          @failed += 1
          @failures << {
            name: name,
            source: source_file,
            template: template,
            expected: expected,
            actual: actual,
            environment: environment
          }
        end
      else
        # Command failed
        print 'E'
        @errors += 1
        @failures << {
          name: name,
          source: source_file,
          template: template,
          expected: expected,
          actual: "ERROR: #{stderr}",
          environment: environment
        }
      end
    rescue Timeout::Error
      print 'T'
      @errors += 1
      @failures << {
        name: name,
        source: source_file,
        template: template,
        expected: expected,
        actual: "TIMEOUT",
        environment: environment
      }
    ensure
      FileUtils.rm_f(template_file)
    end
  end

  def make_json_serializable(obj)
    case obj
    when Hash
      obj.transform_values { |v| make_json_serializable(v) }
    when Array
      obj.map { |v| make_json_serializable(v) }
    when Range
      obj.to_a
    when Set
      obj.to_a
    when Symbol
      obj.to_s
    when Integer, Float, String, TrueClass, FalseClass, NilClass
      obj
    else
      # Skip tests with unsupported types
      raise "Unsupported type: #{obj.class}"
    end
  end

  def print_summary
    puts
    puts
    puts "=" * 60
    puts "Test Results Summary"
    puts "=" * 60
    puts "Passed:  #{@passed}"
    puts "Failed:  #{@failed}"
    puts "Errors:  #{@errors}"
    puts "Skipped: #{@skipped}"
    puts "Total:   #{@passed + @failed + @errors + @skipped}"
    puts

    if @failures.any?
      puts "Failures (first 20):"
      puts "-" * 60
      @failures.first(20).each do |f|
        puts
        puts "Test: #{f[:name]}"
        puts "File: #{f[:source]}"
        puts "Template: #{f[:template].inspect[0..100]}"
        if f[:environment] && !f[:environment].empty?
          puts "Data: #{f[:environment].to_json[0..100]}"
        end
        puts "Expected: #{f[:expected].inspect[0..200]}"
        puts "Actual:   #{f[:actual].inspect[0..200]}"
      end
    end
  end
end

# Run the tests
runner = LiquidSpecRunner.new
runner.run
