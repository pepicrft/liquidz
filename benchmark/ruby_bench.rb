#!/usr/bin/env ruby
# Ruby Liquid benchmark - matches the Zig bench tool behavior
# Pre-parses template, then renders N times

require 'liquid'
require 'json'

if ARGV.length < 2
  puts "Usage: ruby_bench.rb <template-file> <json-file> [iterations]"
  exit 1
end

template_path = ARGV[0]
data_path = ARGV[1]
iterations = (ARGV[2] || 1000).to_i

# Read and parse template once
template_content = File.read(template_path)
template = Liquid::Template.parse(template_content)

# Read JSON data once
data = JSON.parse(File.read(data_path))

# Warm up
5.times { template.render(data) }

# Benchmark
times = []
iterations.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  template.render(data)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start
  times << elapsed
end

avg = times.sum / times.size.to_f
min = times.min
max = times.max
median = times.sort[times.size / 2]
stddev = Math.sqrt(times.map { |t| (t - avg) ** 2 }.sum / times.size)

puts "Iterations: #{iterations}"
puts "Avg: #{avg.round(2)} µs"
puts "Min: #{min} µs"
puts "Max: #{max} µs"
puts "Median: #{median} µs"
puts "StdDev: #{stddev.round(2)} µs"
