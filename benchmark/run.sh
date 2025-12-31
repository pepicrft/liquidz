#!/bin/bash
# Liquidz vs Ruby Liquid Benchmark Script
# Usage: ./run.sh [template_path] [iterations] [--hyperfine]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_FILE="$SCRIPT_DIR/shopify_mock_data.json"
ITERATIONS=${2:-1000}
USE_HYPERFINE=false

# Check for --hyperfine flag
for arg in "$@"; do
    if [ "$arg" = "--hyperfine" ]; then
        USE_HYPERFINE=true
    fi
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Build Liquidz in release mode
echo -e "${BLUE}Building Liquidz (ReleaseFast)...${NC}"
cd "$PROJECT_DIR"
zig build -Doptimize=ReleaseFast
BENCH="$PROJECT_DIR/zig-out/bin/bench"
RUBY_BENCH="$SCRIPT_DIR/ruby_bench.rb"

# Check Ruby is available
if ! command -v ruby &> /dev/null; then
    echo -e "${RED}Ruby not found. Install Ruby to run comparisons.${NC}"
    exit 1
fi

# Create Ruby benchmark script
RUBY_SCRIPT=$(mktemp)
cat > "$RUBY_SCRIPT" << 'RUBY_EOF'
require 'liquid'
require 'json'
require 'benchmark'

template_path = ARGV[0]
data_path = ARGV[1]
iterations = (ARGV[2] || 100).to_i

template_content = File.read(template_path)
data = JSON.parse(File.read(data_path))

# Pre-parse the template
template = Liquid::Template.parse(template_content)

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

puts "#{avg.round(2)},#{min},#{max},#{median}"
RUBY_EOF

benchmark_template() {
    local template="$1"
    local name="$2"

    echo -e "\n${YELLOW}=== Benchmarking: $name ===${NC}"
    echo "Template: $template"
    echo "Iterations: $ITERATIONS"
    echo ""

    if [ "$USE_HYPERFINE" = true ] && command -v hyperfine &> /dev/null; then
        # Use hyperfine for statistical rigor
        echo -e "${GREEN}Running hyperfine benchmark (10 runs each)...${NC}"
        hyperfine \
            --warmup 3 \
            --runs 10 \
            --export-markdown /tmp/bench_result.md \
            -n "Liquidz" "$BENCH $template $DATA_FILE $ITERATIONS" \
            -n "Ruby Liquid" "ruby $RUBY_BENCH $template $DATA_FILE $ITERATIONS" \
            2>&1
        echo ""
        cat /tmp/bench_result.md
    else
        # Simple benchmark
        echo -e "${GREEN}Liquidz:${NC}"
        local liquidz_output=$("$BENCH" "$template" "$DATA_FILE" "$ITERATIONS" 2>&1)
        echo "$liquidz_output" | grep -E "^(Avg|Min|Max):" | sed 's/^/  /'

        echo -e "${GREEN}Ruby Liquid:${NC}"
        local ruby_output=$(ruby "$RUBY_BENCH" "$template" "$DATA_FILE" "$ITERATIONS" 2>/dev/null || echo "ERROR")

        if [ "$ruby_output" = "ERROR" ]; then
            echo "  Failed to run Ruby benchmark"
        else
            echo "$ruby_output" | grep -E "^(Avg|Min|Max):" | sed 's/^/  /'

            # Calculate speedup
            local liquidz_avg=$(echo "$liquidz_output" | grep "Avg:" | awk '{print $2}')
            local ruby_avg=$(echo "$ruby_output" | grep "Avg:" | awk '{print $2}')
            if [ -n "$ruby_avg" ] && [ -n "$liquidz_avg" ] && [ "$liquidz_avg" != "0" ]; then
                local speedup=$(echo "scale=2; $ruby_avg / $liquidz_avg" | bc 2>/dev/null || echo "N/A")
                echo -e "\n${BLUE}Liquidz is ${speedup}x faster${NC}"
            fi
        fi
    fi
}

# If a specific template is provided, benchmark just that
if [ -n "$1" ]; then
    if [ -f "$1" ]; then
        benchmark_template "$1" "$(basename "$1")"
    else
        echo -e "${RED}Template not found: $1${NC}"
        exit 1
    fi
else
    # Benchmark all Dawn templates
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Liquidz vs Ruby Liquid Benchmark Suite               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

    # Find all .liquid files in the Dawn theme
    total_templates=0
    successful_templates=0
    total_liquidz_time=0
    total_ruby_time=0

    # Summary arrays
    declare -a results

    while IFS= read -r template; do
        total_templates=$((total_templates + 1))
        name=$(basename "$template")
        rel_path="${template#$SCRIPT_DIR/themes/dawn/}"

        echo -e "\n${YELLOW}[$total_templates] $rel_path${NC}"

        # Run Liquidz benchmark
        liquidz_output=$("$BENCH" "$template" "$DATA_FILE" "$ITERATIONS" 2>&1) || liquidz_output="ERROR"

        if echo "$liquidz_output" | grep -q "^Avg:"; then
            liquidz_avg=$(echo "$liquidz_output" | grep "Avg:" | awk '{print $2}')
        else
            echo "  Liquidz: FAILED"
            continue
        fi

        # Run Ruby benchmark
        ruby_output=$(ruby "$RUBY_BENCH" "$template" "$DATA_FILE" "$ITERATIONS" 2>/dev/null) || ruby_output="ERROR"

        if echo "$ruby_output" | grep -q "^Avg:"; then
            ruby_avg=$(echo "$ruby_output" | grep "Avg:" | awk '{print $2}')
        else
            echo "  Liquidz: ${liquidz_avg} µs | Ruby: FAILED"
            continue
        fi

        successful_templates=$((successful_templates + 1))

        # Calculate speedup
        if [ "$liquidz_avg" != "0" ] && [ -n "$liquidz_avg" ] && [ -n "$ruby_avg" ]; then
            speedup=$(echo "scale=2; $ruby_avg / $liquidz_avg" | bc 2>/dev/null || echo "N/A")
            echo "  Liquidz: ${liquidz_avg} µs | Ruby: ${ruby_avg} µs | ${speedup}x faster"

            # Accumulate for average
            total_liquidz_time=$(echo "$total_liquidz_time + $liquidz_avg" | bc)
            total_ruby_time=$(echo "$total_ruby_time + $ruby_avg" | bc)
        else
            echo "  Liquidz: ${liquidz_avg} µs | Ruby: ${ruby_avg} µs"
        fi

    done < <(find "$SCRIPT_DIR/themes/dawn" -name "*.liquid" -type f | sort)

    # Print summary
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                        SUMMARY                             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo "Total templates: $total_templates"
    echo "Successfully benchmarked: $successful_templates"

    if [ "$successful_templates" -gt 0 ]; then
        avg_liquidz=$(echo "scale=2; $total_liquidz_time / $successful_templates" | bc)
        avg_ruby=$(echo "scale=2; $total_ruby_time / $successful_templates" | bc)
        overall_speedup=$(echo "scale=2; $total_ruby_time / $total_liquidz_time" | bc 2>/dev/null || echo "N/A")

        echo -e "\nAverage render time:"
        echo "  Liquidz: ${avg_liquidz} µs"
        echo "  Ruby:    ${avg_ruby} µs"
        echo -e "\n${GREEN}Overall: Liquidz is ${overall_speedup}x faster${NC}"
    fi
fi

# Cleanup
rm -f "$RUBY_SCRIPT"

echo -e "\n${GREEN}Benchmark complete!${NC}"
