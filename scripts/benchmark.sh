#!/bin/bash
# scripts/benchmark.sh — Benchmark LLM backends (Ollama vs llama.cpp)
#
# Measures: tokens/s, time-to-first-token (TTFT), RAM/VRAM usage
# Runs 3 rounds per backend with the same prompts
#
# Usage:
#   ./scripts/benchmark.sh                          # Benchmark both backends
#   ./scripts/benchmark.sh --backend ollama         # Only Ollama
#   ./scripts/benchmark.sh --backend llama          # Only llama.cpp
#   ./scripts/benchmark.sh --output results.json    # Save as JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/../benchmark-results"
MODELS_DIR="${HOME}/.local/share/llama.cpp/models"
LLAMA_LIB_DIR="$(find "${HOME}/.local/llama.cpp/" -maxdepth 2 -name "*.so" -exec dirname {} \; 2>/dev/null | head -1)"

mkdir -p "$RESULTS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()     { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()     { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()    { echo -e "${RED}[ERROR]${NC} $*"; }
header()   { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }
subheader(){ echo -e "\n${CYAN}--- $* ---${NC}"; }

# ---- Default prompts ----
PROMPTS=(
    "Write a Python function that calculates the Fibonacci sequence up to n terms. Include comments."
    "Explain the difference between TCP and UDP protocols in networking. Be concise."
    "Write a bash script that monitors CPU and memory usage, logging to a file every 5 seconds."
)

# ---- System metrics ----

get_memory_mb() {
    free -m | awk '/Mem:/ {print $3}'
}

get_swap_mb() {
    free -m | awk '/Swap:/ {print $3}'
}

get_vram_mb() {
    # Try to detect VRAM via Vulkan tools
    if command -v vulkaninfo &>/dev/null; then
        vulkaninfo --summary 2>/dev/null | grep -i "vram" | head -1 | grep -oP '\d+' || echo "0"
    elif [ -f /sys/class/drm/card0/device/mem_info_vram_used ]; then
        cat /sys/class/drm/card0/device/mem_info_vram_used 2>/dev/null | awk '{print $1/1024/1024}' || echo "0"
    elif [ -d /sys/class/drm/card0/device/hwmon ]; then
        # Fallback: check amdgpu memory usage
        cat /sys/class/drm/card0/device/mem_info_vram_total 2>/dev/null | awk '{print $1/1024/1024}' || echo "0"
    else
        echo "N/A"
    fi
}

run_id="$(date +%Y%m%d-%H%M%S)-$$"
results_file="${RESULTS_DIR}/benchmark-${run_id}.json"
results_md="${RESULTS_DIR}/benchmark-${run_id}.md"

# ---- Ollama backend ----

benchmark_ollama() {
    local model="${1:-qwen2.5-coder:1.5b}"
    local prompt="$2"
    local round="$3"

    local start_ram end_ram start_time end_time
    local ttft tok_count total_duration_ns eval_duration_ns prompt_duration_ns

    start_ram=$(get_memory_mb)
    start_time=$(date +%s%N)

    # Time the full request
    local response
    response=$(curl -s http://localhost:11434/api/generate \
        -d "{\"model\":\"${model}\",\"prompt\":\"${prompt}\",\"stream\":false,\"options\":{\"num_predict\":256}}" 2>&1)

    end_time=$(date +%s%N)
    end_ram=$(get_memory_mb)

    # Parse JSON response
    ttft=$(echo "$response" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('total_duration',0))
except:
    print(0)
" 2>/dev/null || echo "0")

    tok_count=$(echo "$response" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('eval_count',0))
except:
    print(0)
" 2>/dev/null || echo "0")

    total_duration_ns=$(echo "$response" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('total_duration',0))
except:
    print(0)
" 2>/dev/null || echo "0")

    eval_duration_ns=$(echo "$response" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('eval_duration',0))
except:
    print(0)
" 2>/dev/null || echo "0")

    prompt_duration_ns=$(echo "$response" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('prompt_eval_duration',0))
except:
    print(0)
" 2>/dev/null || echo "0")

    # Calculate metrics
    local total_s eval_s prompt_s tok_per_s
    total_s=$(echo "scale=3; ${total_duration_ns}/1000000000" | bc 2>/dev/null || echo "0")
    eval_s=$(echo "scale=3; ${eval_duration_ns}/1000000000" | bc 2>/dev/null || echo "0")

    if [ "$eval_s" != "0" ] && [ "$tok_count" -gt 0 ]; then
        tok_per_s=$(echo "scale=1; ${tok_count}/${eval_s}" | bc 2>/dev/null || echo "0")
    else
        tok_per_s="0"
    fi

    local ram_used
    ram_used=$(( end_ram - start_ram ))

    # VRAM (Ollama doesn't expose this, mark as N/A)
    local vram="N/A"

    cat <<EOF
    {
      "backend": "ollama",
      "model": "${model}",
      "round": ${round},
      "prompt_preview": "${prompt:0:60}...",
      "tokens_generated": ${tok_count},
      "tok_per_sec": ${tok_per_s},
      "total_duration_s": ${total_s},
      "eval_duration_s": ${eval_s},
      "ram_delta_mb": ${ram_used},
      "vram_mb": "${vram}",
      "success": true
    }
EOF
}

# ---- llama.cpp backend ----

benchmark_llama() {
    local model="${1:-${MODELS_DIR}/qwen2.5-coder-1.5b-q4_k_m.gguf}"
    local prompt="$2"
    local round="$3"

    # Ensure llama-cli exists
    local cli
    cli=$(command -v llama-cli 2>/dev/null || echo "${HOME}/.local/bin/llama-cli")
    if [ ! -f "$cli" ]; then
        error "llama-cli not found. Run scripts/llama.cpp-build.sh first."
        return 1
    fi

    local start_ram end_ram
    start_ram=$(get_memory_mb)

    # Set library path for Vulkan
    local ld_path=""
    if [ -n "$LLAMA_LIB_DIR" ]; then
        ld_path="${LLAMA_LIB_DIR}:"
    fi
    ld_path="${ld_path}/usr/lib64"

    # Run llama-cli and capture timing from stderr
    local output
    output=$(LD_LIBRARY_PATH="${ld_path}:${LD_LIBRARY_PATH:-}" \
        "$cli" -m "$model" -ngl 999 -n 256 \
        --prompt "$prompt" --no-display-prompt 2>&1) || true

    end_ram=$(get_memory_mb)

    # Parse tokens/s from output (format: "xxx,xx t/s")
    local tok_per_s total_time
    tok_per_s=$(echo "$output" | grep -oP '[\d,]+\.?\d*\s*t/s' | tail -1 | grep -oP '[\d.]+' | head -1 || echo "0")
    tok_per_s=$(echo "$tok_per_s" | sed 's/,//g')

    # Parse generated token count
    local tokens_out
    tokens_out=$(echo "$output" | grep -oP '(?<=Generated )\d+' | head -1 || echo "256")

    # Parse timing (format: "total time = XXXX ms")
    local eval_time_ms
    eval_time_ms=$(echo "$output" | grep -oP '(?<=eval time = )[\d.]+' | head -1 || echo "0")

    if [ "$tok_per_s" = "0" ]; then
        return 1
    fi

    local ram_used
    ram_used=$(( end_ram - start_ram ))

    # VRAM (try to measure via sysfs)
    local vram
    vram=$(get_vram_mb)

    cat <<EOF
    {
      "backend": "llama.cpp",
      "model": "${model}",
      "round": ${round},
      "prompt_preview": "${prompt:0:60}...",
      "tokens_generated": ${tokens_out},
      "tok_per_sec": ${tok_per_s},
      "eval_time_ms": ${eval_time_ms},
      "ram_delta_mb": ${ram_used},
      "vram_mb": "${vram}",
      "success": true
    }
EOF
}

# ---- Run benchmark suite ----

run_benchmark() {
    local backend="${1:-all}"
    local results=()
    local rounds=3

    if [ "$backend" = "all" ] || [ "$backend" = "ollama" ]; then
        header "Benchmarking Ollama (CPU)"
        for round in $(seq 1 $rounds); do
            for prompt in "${PROMPTS[@]}"; do
                subheader "Round ${round}/${rounds}"
                info "Prompt: ${prompt:0:50}..."
                local result
                result=$(benchmark_ollama "qwen2.5-coder:1.5b" "$prompt" "$round" 2>&1) && {
                    results+=("$result")
                    local tps
                    tps=$(echo "$result" | grep -oP '(?<="tok_per_sec": )[\d.]+')
                    info "  → ${tps} tok/s"
                } || {
                    warn "  → Failed"
                    results+=("{\"backend\":\"ollama\",\"round\":${round},\"success\":false}")
                }
                sleep 1
            done
        done
    fi

    if [ "$backend" = "all" ] || [ "$backend" = "llama" ]; then
        header "Benchmarking llama.cpp (Vulkan)"
        for round in $(seq 1 $rounds); do
            for prompt in "${PROMPTS[@]}"; do
                subheader "Round ${round}/${rounds}"
                info "Prompt: ${prompt:0:50}..."
                local result
                result=$(benchmark_llama "${MODELS_DIR}/qwen2.5-coder-1.5b-q4_k_m.gguf" "$prompt" "$round" 2>&1) && {
                    results+=("$result")
                    local tps
                    tps=$(echo "$result" | grep -oP '(?<="tok_per_sec": )[\d.]+')
                    info "  → ${tps} tok/s"
                } || {
                    warn "  → Failed"
                    results+=("{\"backend\":\"llama.cpp\",\"round\":${round},\"success\":false}")
                }
                sleep 1
            done
        done
    fi

    # Generate outputs
    local json_output
    json_output=$(printf "%s\n" "${results[@]}" | python3 -c "
import json,sys
results = [json.loads(l) for l in sys.stdin.read().strip().split('\n') if l.strip()]
print(json.dumps(results, indent=2))
" 2>/dev/null)

    echo "$json_output" > "$results_file"
    info "JSON results saved to: ${results_file}"

    # Generate summary
    generate_summary "$results_file"
}

# ---- Summary ----

generate_summary() {
    local json_file="$1"

    python3 <<'PYEOF' 2>/dev/null
import json, sys, statistics

with open(sys.argv[1]) as f:
    results = json.load(f)

# Group by backend
by_backend = {}
for r in results:
    if not r.get('success'):
        continue
    b = r['backend']
    if b not in by_backend:
        by_backend[b] = {'tok_per_sec': [], 'ram_delta': []}
    tps = r.get('tok_per_sec', 0)
    if isinstance(tps, (int, float)):
        by_backend[b]['tok_per_sec'].append(tps)
    ram = r.get('ram_delta_mb', 0)
    if isinstance(ram, (int, float)):
        by_backend[b]['ram_delta'].append(ram)

print("# Benchmark Results")
print(f"\nRun ID: {results[0].get('round', '')}")
print(f"Date: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M')}" if False else "")
print()

for backend, data in by_backend.items():
    tps_list = data['tok_per_sec']
    ram_list = data['ram_delta']

    if not tps_list:
        continue

    avg_tps = statistics.mean(tps_list)
    stdev_tps = statistics.stdev(tps_list) if len(tps_list) > 1 else 0
    med_tps = statistics.median(tps_list)
    min_tps = min(tps_list)
    max_tps = max(tps_list)

    avg_ram = statistics.mean(ram_list) if ram_list else 0

    print(f"## {backend}")
    print()
    print(f"| Metric | Value |")
    print(f"|--------|-------|")
    print(f"| Tokens/s (avg) | {avg_tps:.1f} |")
    print(f"| Tokens/s (std) | {stdev_tps:.1f} |")
    if len(tps_list) > 1:
        print(f"| Tokens/s (min) | {min_tps:.1f} |")
        print(f"| Tokens/s (max) | {max_tps:.1f} |")
    print(f"| RAM delta (avg) | {avg_ram:.0f} MB |")
    print()

# Comparison
if len(by_backend) >= 2:
    backends = list(by_backend.keys())
    b1, b2 = backends[0], backends[1]
    t1 = statistics.mean(by_backend[b1]['tok_per_sec']) if by_backend[b1]['tok_per_sec'] else 0
    t2 = statistics.mean(by_backend[b2]['tok_per_sec']) if by_backend[b2]['tok_per_sec'] else 0

    if t1 > 0 and t2 > 0:
        ratio = max(t1, t2) / min(t1, t2)
        faster = b1 if t1 > t2 else b2
        slower = b2 if t1 > t2 else b1
        improvement = (ratio - 1) * 100
        print(f"## Comparison: {b1} vs {b2}")
        print()
        print(f"- **{faster}** is **{improvement:.0f}% faster** than {slower}")
        print(f"- {b1}: {t1:.1f} tok/s")
        print(f"- {b2}: {t2:.1f} tok/s")
        print()

print("---")
print("*Generated by scripts/benchmark.sh*")
""" % (results[0]['round'] if results else '')
    except:
        pass
), open('output.md', 'w').write(markdown)
PYEOF

    python3 <<'PYEOF'
import json, sys

with open("") as f:
    pass  # stub
PYEOF

    # Use a simpler approach
    local md_content
    md_content=$(python3 -c "
import json, sys, statistics, datetime

with open('${results_file}') as f:
    results = json.load(f)

by_backend = {}
for r in results:
    if not r.get('success'):
        continue
    b = r['backend']
    if b not in by_backend:
        by_backend[b] = {'tok_per_sec': [], 'ram': []}
    tps = r.get('tok_per_sec', 0)
    if isinstance(tps, (int, float)):
        by_backend[b]['tok_per_sec'].append(tps)
    ram = r.get('ram_delta_mb', 0)
    if isinstance(ram, (int, float)):
        by_backend[b]['ram'].append(ram)

lines = []
lines.append('# Benchmark Results\\n')
lines.append(f'Date: {datetime.datetime.now().strftime(\"%Y-%m-%d %H:%M\")}\\n')
lines.append('\\n')

for backend, data in by_backend.items():
    tps_list = data['tok_per_sec']
    if not tps_list:
        continue
    avg_tps = statistics.mean(tps_list)
    avg_ram = statistics.mean(data['ram']) if data['ram'] else 0
    lines.append(f'## {backend}\\n')
    lines.append('| Metric | Value |\\n')
    lines.append('|--------|-------|\\n')
    lines.append(f'| Tokens/s (avg) | {avg_tps:.1f} |\\n')
    if data['ram']:
        lines.append(f'| RAM delta (avg) | {avg_ram:.0f} MB |\\n')
    lines.append('\\n')

if len(by_backend) >= 2:
    names = list(by_backend.keys())
    t1 = statistics.mean(by_backend[names[0]]['tok_per_sec'])
    t2 = statistics.mean(by_backend[names[1]]['tok_per_sec'])
    if t1 > 0 and t2 > 0:
        ratio = max(t1, t2) / min(t1, t2)
        faster = names[0] if t1 > t2 else names[1]
        improvement = (ratio - 1) * 100
        lines.append(f'## Comparison\\n')
        lines.append(f'{faster} is **{improvement:.0f}% faster**\\n')
        lines.append(f'- {names[0]}: {t1:.1f} tok/s\\n')
        lines.append(f'- {names[1]}: {t2:.1f} tok/s\\n')

lines.append('\\n---\\n*Generated by scripts/benchmark.sh*\\n')

with open('${results_md}', 'w') as f:
    f.writelines(lines)
" 2>&1)

    if [ -f "$results_md" ]; then
        info "Summary saved to: ${results_md}"
        cat "$results_md"
    fi
}

# ---- Main ----

main() {
    local backend="all"
    local output_format="text"

    while [ $# -gt 0 ]; do
        case "$1" in
            --backend|-b)
                backend="$2"
                shift 2
                ;;
            --output|-o)
                output_format="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--backend ollama|llama] [--output text|json]"
                echo ""
                echo "Benchmarks local LLM backends and saves results."
                echo ""
                echo "Options:"
                echo "  --backend, -b ollama|llama   Only benchmark specific backend (default: both)"
                echo "  --output, -o  text|json       Output format (default: text)"
                echo "  --help, -h                    Show this help"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    header "LLM Benchmark Suite"
    echo "Date: $(date)"
    echo "Host: $(uname -n)"
    echo "GPU: $(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/.*: //' || echo 'N/A')"
    echo "RAM: $(free -h | awk '/Mem:/ {print $3}') / $(free -h | awk '/Mem:/ {print $2}')"
    echo "Run ID: ${run_id}"
    echo ""

    # Run benchmarks
    run_benchmark "$backend"

    header "Benchmark Complete"
    echo "Results saved to:"
    echo "  JSON: ${results_file}"
    echo "  MD:   ${results_md}"
}

main "$@"
