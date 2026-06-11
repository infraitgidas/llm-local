#!/bin/bash
# scripts/benchmark-final.sh — Final comprehensive benchmark for all profiles
#
# Tests:
#   - Ollama CPU with qwen2.5-coder:1.5b and qwen2.5-coder:3b
#   - llama.cpp Vulkan with 1.5B (if available)
#   - RAG pipeline (query → retrieval)
#   - RAM/VRAM idle vs load
#
# Usage:
#   ./scripts/benchmark-final.sh                    # Run full benchmark
#   ./scripts/benchmark-final.sh --rag-only          # Only RAG test
#   ./scripts/benchmark-final.sh --llm-only          # Only LLM benchmarks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="${PROJECT_DIR}/benchmark-results"
MODELS_DIR="${HOME}/.local/share/llama.cpp/models"

mkdir -p "$RESULTS_DIR"

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

# ---- System Metrics ----

get_memory_mb() {
    free -m | awk '/Mem:/ {print $3}'
}

get_swap_mb() {
    free -m | awk '/Swap:/ {print $3}'
}

get_vram_mb() {
    if [ -f /sys/class/drm/card0/device/mem_info_vram_used ]; then
        local total used
        total=$(cat /sys/class/drm/card0/device/mem_info_vram_total 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 0)
        used=$(cat /sys/class/drm/card0/device/mem_info_vram_used 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 0)
        echo "{\"total_mb\":${total},\"used_mb\":${used}}"
    else
        echo "{\"total_mb\":0,\"used_mb\":0}"
    fi
}

parse_vram_used() {
    echo "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('used_mb', 0))" 2>/dev/null || echo 0
}

parse_vram_total() {
    echo "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_mb', 0))" 2>/dev/null || echo 0
}

# ---- Ollama Benchmark ----

benchmark_ollama() {
    local model="$1"
    local label="$2"
    local prompt="$3"
    
    local start_ram end_ram start_vram end_vram
    start_ram=$(get_memory_mb)
    start_vram=$(get_vram_mb)
    
    local start_time end_time
    start_time=$(date +%s%N)
    
    local response
    response=$(curl -s http://localhost:11434/api/generate \
        -d "{\"model\":\"${model}\",\"prompt\":\"${prompt}\",\"stream\":false,\"options\":{\"num_predict\":128}}" 2>&1)
    
    end_time=$(date +%s%N)
    end_ram=$(get_memory_mb)
    end_vram=$(get_vram_mb)
    
    local total_duration eval_duration eval_count prompt_eval_duration
    total_duration=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('total_duration',0))" 2>/dev/null || echo 0)
    eval_duration=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('eval_duration',0))" 2>/dev/null || echo 0)
    eval_count=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('eval_count',0))" 2>/dev/null || echo 0)
    prompt_eval_duration=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('prompt_eval_duration',0))" 2>/dev/null || echo 0)
    
    local total_s eval_s tok_per_s ttft_ms
    total_s=$(echo "scale=3; ${total_duration}/1000000000" | bc 2>/dev/null || echo 0)
    eval_s=$(echo "scale=3; ${eval_duration}/1000000000" | bc 2>/dev/null || echo 0)
    ttft_ms=$(echo "scale=1; ${prompt_eval_duration}/1000000" | bc 2>/dev/null || echo 0)
    
    if [ "${eval_s}" != "0" ] && [ "${eval_count}" -gt 0 ]; then
        tok_per_s=$(echo "scale=1; ${eval_count}/${eval_s}" | bc 2>/dev/null || echo 0)
    else
        tok_per_s=0
    fi
    
    local ram_delta=$(( end_ram - start_ram ))
    local vram_used_start vram_used_end
    vram_used_start=$(parse_vram_used "$start_vram")
    vram_used_end=$(parse_vram_used "$end_vram")
    local vram_delta=$(( vram_used_end - vram_used_start ))
    
    cat <<BENCH
    {
      "backend": "ollama",
      "model": "${label}",
      "prompt_preview": "${prompt:0:60}...",
      "tokens_generated": ${eval_count},
      "tok_per_sec": ${tok_per_s},
      "ttft_ms": ${ttft_ms},
      "total_duration_s": ${total_s},
      "ram_delta_mb": ${ram_delta},
      "vram_delta_mb": ${vram_delta},
      "ram_idle_mb": ${start_ram},
      "ram_load_mb": ${end_ram},
      "success": true
    }
BENCH
}

# ---- RAG Benchmark ----

benchmark_rag() {
    local query="$1"
    
    info "RAG query: ${query}"
    
    local start_time end_time
    start_time=$(date +%s%N)
    
    local result
    result=$("${SCRIPT_DIR}/rag-query.sh" --raw "${query}" 2>/dev/null || echo '{"error":"RAG query failed"}')
    
    end_time=$(date +%s%N)
    local total_ms
    total_ms=$(( (end_time - start_time) / 1000000 ))
    
    local top_score num_results
    top_score=$(echo "$result" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    results = d.get('results', [])
    if results:
        print(results[0].get('score', 0))
    else:
        print(0)
    print(len(results))
except:
    print(0)
    print(0)
" 2>/dev/null | head -1 || echo 0)
    
    num_results=$(echo "$result" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(len(d.get('results', [])))
except:
    print(0)
" 2>/dev/null || echo 0)
    
    local success=false
    [ "$num_results" -gt 0 ] && success=true
    
    cat <<BENCH
    {
      "test": "rag-query",
      "query_preview": "${query:0:60}...",
      "latency_ms": ${total_ms},
      "top_score": ${top_score},
      "results_count": ${num_results},
      "success": ${success}
    }
BENCH
}

# ---- Full Benchmark Suite ----

run_llm_benchmarks() {
    local results=()
    local prompts=(
        "Write a Python function for Fibonacci sequence with comments."
        "Explain the difference between TCP and UDP."
        "Write a bash script to monitor CPU and memory."
    )
    
    header "Ollama CPU — qwen2.5-coder:1.5b"
    for prompt in "${prompts[@]}"; do
        info "Testing 1.5B: ${prompt:0:40}..."
        local result
        result=$(benchmark_ollama "qwen2.5-coder:1.5b" "qwen2.5-coder:1.5b" "$prompt" 2>&1) && {
            results+=("$result")
            local tps
            tps=$(echo "$result" | grep -oP '(?<="tok_per_sec": )[\d.]+')
            info "  → ${tps} tok/s"
        } || {
            warn "  → Failed"
        }
        sleep 1
    done
    
    header "Ollama CPU — qwen2.5-coder:3b"
    for prompt in "${prompts[@]}"; do
        info "Testing 3B: ${prompt:0:40}..."
        local result
        result=$(benchmark_ollama "qwen2.5-coder:3b" "qwen2.5-coder:3b" "$prompt" 2>&1) && {
            results+=("$result")
            local tps
            tps=$(echo "$result" | grep -oP '(?<="tok_per_sec": )[\d.]+')
            info "  → ${tps} tok/s"
        } || {
            warn "  → Failed"
        }
        sleep 1
    done
    
    # llama.cpp Vulkan (1.5B only — 3B GGUF not downloaded)
    if [ -f "${MODELS_DIR}/qwen2.5-coder-1.5b-q4_k_m.gguf" ]; then
        header "llama.cpp Vulkan — 1.5B"
        # Try using existing benchmark.sh for llama.cpp
        if [ -f "${SCRIPT_DIR}/benchmark.sh" ]; then
            "${SCRIPT_DIR}/benchmark.sh" --backend llama 2>&1 || warn "llama.cpp benchmark failed"
        else
            warn "benchmark.sh not available"
        fi
    else
        warn "llama.cpp models not found — skipping Vulkan benchmarks"
    fi
    
    local json_output
    json_output=$(printf "%s\n" "${results[@]}" | python3 -c "
import json,sys
results = [json.loads(l) for l in sys.stdin.read().strip().split('\n') if l.strip()]
print(json.dumps(results, indent=2))
" 2>/dev/null)
    
    echo "$json_output"
}

run_rag_benchmarks() {
    header "RAG Pipeline Benchmarks"
    
    local queries=(
        "cómo crear una VM con 2 cores y 4GB RAM"
        "how to check service status with systemd"
        "how to backup all VMs in proxmox"
        "comando para listar servicios activos en systemd"
    )
    
    local results=()
    for query in "${queries[@]}"; do
        info "Query: ${query:0:50}..."
        local result
        result=$(benchmark_rag "$query" 2>&1) && {
            results+=("$result")
            local lat score
            lat=$(echo "$result" | grep -oP '(?<="latency_ms": )\d+' || echo "?")
            score=$(echo "$result" | grep -oP '(?<="top_score": )[\d.]+' || echo "?")
            info "  → ${lat}ms | score: ${score}"
        } || {
            warn "  → Failed"
        }
        sleep 0.5
    done
    
    local json_output
    json_output=$(printf "%s\n" "${results[@]}" | python3 -c "
import json,sys
results = [json.loads(l) for l in sys.stdin.read().strip().split('\n') if l.strip()]
print(json.dumps(results, indent=2))
" 2>/dev/null)
    
    echo "$json_output"
}

# ---- Main ----

main() {
    local mode="${1:-full}"
    local results_file="${RESULTS_DIR}/final.json"
    local timestamp
    timestamp=$(date -Iseconds)

    header "Final Benchmark — Setup Local Inference Stack"
    echo "Date:     $(date)"
    echo "Host:     $(uname -n)"
    echo "GPU:      $(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/.*: //' || echo 'N/A')"
    echo "RAM:      $(free -h | awk '/Mem:/ {print $3}') / $(free -h | awk '/Mem:/ {print $2}')"
    echo "Backend:  Ollama + llama.cpp"
    
    # Idle resources
    local idle_ram idle_vram
    idle_ram=$(get_memory_mb)
    idle_vram=$(get_vram_mb)
    
    local idle_vram_used idle_vram_total
    idle_vram_used=$(parse_vram_used "$idle_vram")
    idle_vram_total=$(parse_vram_total "$idle_vram")
    
    local llm_results="[]"
    local rag_results="[]"
    
    if [ "$mode" = "full" ] || [ "$mode" = "llm" ] || [ "$mode" = "--llm-only" ]; then
        llm_results=$(run_llm_benchmarks)
    fi
    
    if [ "$mode" = "full" ] || [ "$mode" = "rag" ] || [ "$mode" = "--rag-only" ]; then
        rag_results=$(run_rag_benchmarks)
    fi
    
    # Load resources
    local load_ram load_vram
    load_ram=$(get_memory_mb)
    load_vram=$(get_vram_mb)
    
    local load_vram_used load_vram_total
    load_vram_used=$(parse_vram_used "$load_vram")
    load_vram_total=$(parse_vram_total "$load_vram")
    
    # Build final report
    python3 <<PYEOF
import json, os, sys, subprocess

llm_results = json.loads("""${llm_results}""") if """${llm_results}""".strip() else []
rag_results = json.loads("""${rag_results}""") if """${rag_results}""".strip() else []

final = {
    "benchmark": "final",
    "timestamp": "${timestamp}",
    "host": "$(uname -n)",
    "gpu": "$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/.*: //' || echo 'N/A')",
    "system": {
        "ram_total_gb": $(free -m | awk '/Mem:/ {print $2}') / 1024.0,
        "ram_idle_mb": ${idle_ram},
        "ram_load_mb": ${load_ram},
        "vram_total_mb": ${idle_vram_total},
        "vram_idle_mb": ${idle_vram_used},
        "vram_load_mb": ${load_vram_used},
        "swap_total_gb": $(free -m | awk '/Swap:/ {print $2}') / 1024.0,
        "swap_used_mb": $(get_swap_mb)
    },
    "available_models": [
        {
            "name": "qwen2.5-coder:1.5b",
            "size_gb": 0.986,
            "quantization": "Q4_K_M",
            "backend": "ollama",
            "vram_estimate_gb": 1.0
        },
        {
            "name": "qwen2.5-coder:3b",
            "size_gb": 1.9,
            "quantization": "Q4_K_M",
            "backend": "ollama",
            "vram_estimate_gb": 1.8
        },
        {
            "name": "qwen2.5-coder-1.5b-q4_k_m.gguf",
            "size_gb": 0.986,
            "quantization": "Q4_K_M",
            "backend": "llama.cpp+vulkan",
            "vram_estimate_gb": 1.0
        },
        {
            "name": "nomic-embed-text",
            "size_gb": 0.274,
            "quantization": "F16",
            "backend": "ollama",
            "vram_estimate_gb": 0.3,
            "purpose": "embeddings"
        }
    ],
    "profiles": [
        {"name": "git", "model": "qwen2.5-coder:1.5b", "temperature": 0.2},
        {"name": "infra", "model": "qwen2.5-coder:3b", "temperature": 0.2},
        {"name": "doc", "model": "qwen2.5-coder:3b", "temperature": 0.4},
        {"name": "proxmox", "model": "qwen2.5-coder:3b", "temperature": 0.2}
    ],
    "llm_benchmarks": llm_results,
    "rag_benchmarks": rag_results,
    "rag_index": {
        "path": "rag-index/docs.json",
        "chunks": 8,
        "source_files": ["docs/proxmox-basics.md", "docs/infra-basics.md"]
    },
    "summary": {}
}

# Calculate averages
if llm_results:
    for backend_model in ["qwen2.5-coder:1.5b", "qwen2.5-coder:3b"]:
        stats = [r for r in llm_results if r.get("model") == backend_model and r.get("success")]
        if stats:
            tps_list = [r.get("tok_per_sec", 0) for r in stats if r.get("tok_per_sec", 0) > 0]
            if tps_list:
                avg_tps = sum(tps_list) / len(tps_list)
                final["summary"][f"{backend_model}_avg_tps"] = round(avg_tps, 1)
            
            ram_list = [r.get("ram_delta_mb", 0) for r in stats]
            if ram_list:
                avg_ram = sum(ram_list) / len(ram_list)
                final["summary"][f"{backend_model}_avg_ram_mb"] = round(avg_ram, 0)
            
            ttft_list = [r.get("ttft_ms", 0) for r in stats if r.get("ttft_ms", 0) > 0]
            if ttft_list:
                avg_ttft = sum(ttft_list) / len(ttft_list)
                final["summary"][f"{backend_model}_avg_ttft_ms"] = round(avg_ttft, 0)

if rag_results:
    rag_times = [r.get("latency_ms", 0) for r in rag_results if r.get("success")]
    if rag_times:
        final["summary"]["rag_avg_latency_ms"] = round(sum(rag_times) / len(rag_times), 0)
    rag_success = [r for r in rag_results if r.get("success")]
    final["summary"]["rag_queries_total"] = len(rag_results)
    final["summary"]["rag_queries_success"] = len(rag_success)

# Resource check
ram_pct = (${load_ram} / $(free -m | awk '/Mem:/ {print $2}')) * 100
final["summary"]["ram_usage_pct"] = round(ram_pct, 1)
if ${idle_vram_total} > 0:
    vram_pct = (${load_vram_used} / ${idle_vram_total}) * 100
    final["summary"]["vram_usage_pct"] = round(vram_pct, 1)

# Resource constraints check
constraints = []
if ram_pct > 85:
    constraints.append(f"RAM usage {ram_pct:.0f}% exceeds 85% threshold")
if ${load_vram_used} > 0 and ${idle_vram_total} > 0:
    vram_pct = (${load_vram_used} / ${idle_vram_total}) * 100
    if vram_pct > 85:
        constraints.append(f"VRAM usage {vram_pct:.0f}% exceeds 85% threshold")

final["summary"]["constraints"] = constraints
final["summary"]["constraints_ok"] = len(constraints) == 0

with open("${results_file}", "w") as f:
    json.dump(final, f, indent=2)

print(f"Final benchmark saved to: ${results_file}")
if constraints:
    for c in constraints:
        print(f"  ⚠  {c}")
else:
    print("  ✓ All resource constraints satisfied")
PYEOF

    echo ""
    header "Benchmark Complete"
    echo "Results: ${results_file}"
    
    # Print summary
    python3 -c "
import json
with open('${results_file}') as f:
    d = json.load(f)
s = d.get('summary', {})
print()
print('=== SUMMARY ===')
for k, v in s.items():
    if k != 'constraints':
        print(f'  {k}: {v}')
if s.get('constraints'):
    print(f'  constraints: {s[\"constraints\"]}')
"
}

main "$@"
