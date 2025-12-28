#!/usr/bin/env ruby
# frozen_string_literal: true

# Golden Liquid Test Runner for Liquidz
#
# This script runs the golden-liquid test suite against the liquidz binary
# and reports the results.

require 'json'
require 'open3'
require 'optparse'

class GoldenLiquidTestRunner
  def initialize(liquidz_binary, test_dir, options = {})
    @liquidz_binary = liquidz_binary
    @test_dir = test_dir
    @verbose = options[:verbose] || false
    @filter = options[:filter]
    @skip_strict = options[:skip_strict] || false
    @results = { passed: 0, failed: 0, skipped: 0, errors: [] }
  end

  def run
    puts "Running Golden Liquid tests..."
    puts "Binary: #{@liquidz_binary}"
    puts "Test directory: #{@test_dir}"
    puts

    # Load all test files
    test_files = Dir.glob(File.join(@test_dir, '**', '*.json'))
    test_files.reject! { |f| f.include?('schema') || f.include?('benchmark') }

    test_files.each do |test_file|
      run_test_file(test_file)
    end

    print_summary
    @results[:failed] == 0
  end

  private

  def run_test_file(test_file)
    relative_path = test_file.sub("#{@test_dir}/", '')
    data = JSON.parse(File.read(test_file))

    tests = data['tests'] || []
    return if tests.empty?

    puts "Running: #{relative_path}" if @verbose

    tests.each do |test|
      run_single_test(test, relative_path)
    end
  end

  def run_single_test(test, file_path)
    name = test['name']
    template = test['template']
    context_data = (test['data'] || {}).dup
    templates = test['templates']
    context_data['__templates'] = templates if templates
    expected = test['result']
    expected_results = test['results'] # Some tests have multiple valid results
    invalid = test['invalid'] || false
    tags = test['tags'] || []

    # Skip filters
    return skip_test(name, 'filtered out') if @filter && !name.include?(@filter)
    return skip_test(name, 'strict mode') if @skip_strict && tags.include?('strict')
    return skip_test(name, 'invalid template') if invalid

    # Run the template through liquidz
    begin
      actual = render_template(template, context_data)

      # Check results
      if expected_results
        # Multiple valid results
        if expected_results.any? { |r| normalize(r) == normalize(actual) }
          pass_test(name)
        else
          fail_test(name, file_path, expected_results.first, actual, template, context_data)
        end
      elsif expected
        if normalize(expected) == normalize(actual)
          pass_test(name)
        else
          fail_test(name, file_path, expected, actual, template, context_data)
        end
      else
        # No expected result, just check it doesn't crash
        pass_test(name)
      end
    rescue StandardError => e
      error_test(name, file_path, e.message, template)
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
    str.to_s.strip
  end

  def pass_test(name)
    @results[:passed] += 1
    print '.' unless @verbose
    puts "  PASS: #{name}" if @verbose
  end

  def fail_test(name, file_path, expected, actual, template, context)
    @results[:failed] += 1
    print 'F' unless @verbose

    @results[:errors] << {
      name: name,
      file: file_path,
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

  def error_test(name, file_path, error, template)
    @results[:failed] += 1
    print 'E' unless @verbose

    @results[:errors] << {
      name: name,
      file: file_path,
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
    puts "Test Results Summary"
    puts "=" * 60
    puts "Passed:  #{@results[:passed]}"
    puts "Failed:  #{@results[:failed]}"
    puts "Skipped: #{@results[:skipped]}"
    puts "Total:   #{@results[:passed] + @results[:failed] + @results[:skipped]}"
    puts

    if @results[:errors].any?
      puts "Failures:"
      puts "-" * 60
      @results[:errors].first(10).each do |error|
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

      if @results[:errors].size > 10
        puts
        puts "... and #{@results[:errors].size - 10} more failures"
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

  opts.on('--skip-strict', 'Skip strict mode tests') do
    options[:skip_strict] = true
  end

  opts.on('-b', '--binary PATH', 'Path to liquidz binary') do |path|
    options[:binary] = path
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
test_dir = File.join(script_dir, 'golden-liquid', 'tests')

unless File.exist?(liquidz_binary)
  puts "Error: liquidz binary not found at #{liquidz_binary}"
  puts "Please build the project first with: zig build"
  exit 1
end

unless File.directory?(test_dir)
  puts "Error: Test directory not found at #{test_dir}"
  exit 1
end

runner = GoldenLiquidTestRunner.new(liquidz_binary, test_dir, options)
success = runner.run

exit(success ? 0 : 1)
