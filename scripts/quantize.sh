#!/bin/bash
# scripts/quantize.sh — Quantize FP16 GGUF models using llama.cpp
#
# Usage:
#   ./scripts/quantize.sh <input.gguf> <type>     # Quantize model
#   ./scripts/quantize.sh list                     # List available quant types
#   ./scripts/quantize.sh check                    # Check if quantize tool exists
#
# Types: Q4_K_M (default), Q5_K_M, Q8_0, Q4_0, Q6_K

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODELS_DIR="${PROJECT_DIR}/models"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Find llama.cpp quantize tool
find_quantize() {
    # Try various locations
    local paths=(
        "$(command -v llama-quantize 2>/dev/null || true)"
        "${HOME}/.local/bin/llama-quantize"
        "${PROJECT_DIR}/llama.cpp/build/bin/llama-quantize"
        "${PROJECT_DIR}/llama.cpp/build/bin/quantize"
    )
    
    for p in "${paths[@]}"; do
        if [ -f "$p" ] && [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    
    # Also check if llama.cpp build exists
    if [ -d "${PROJECT_DIR}/llama.cpp" ]; then
        warn "llama.cpp found but quantize tool not built"
        info "Build it with: cd llama.cpp && make llama-quantize -j"
    fi
    
    return 1
}

# Check prerequisites
check_tool() {
    if find_quantize >/dev/null 2>&1; then
        info "Quantize tool found: $(find_quantize)"
        return 0
    else
        error "llama-quantize not found."
        info "Build llama.cpp first: ./scripts/llama.cpp-build.sh"
        return 1
    fi
}

# Do the quantization
do_quantize() {
    local input="$1"
    local quant_type="${2:-Q4_K_M}"
    
    # Validate input file
    if [ ! -f "$input" ]; then
        # Try in models/ directory
        local alt="${MODELS_DIR}/${input}"
        if [ -f "$alt" ]; then
            input="$alt"
        else
            error "Input file not found: ${input}"
            exit 1
        fi
    fi
    
    # Get quantize tool
    local quantize
    quantize=$(find_quantize) || {
        error "llama-quantize not available. Build llama.cpp first."
        exit 1
    }
    
    # Validate quant type
    local valid_types=("Q4_0" "Q4_K_M" "Q5_K_M" "Q8_0" "Q6_K" "Q3_K_M" "Q2_K")
    local valid=false
    for vt in "${valid_types[@]}"; do
        [ "$vt" = "$quant_type" ] && valid=true && break
    done
    if [ "$valid" = false ]; then
        error "Invalid quantization type: ${quant_type}"
        echo "Valid types: ${valid_types[*]}"
        exit 1
    fi
    
    # Build output path
    local dir ext base output
    dir=$(dirname "$input")
    base=$(basename "$input" .gguf)
    output="${dir}/${base}-${quant_type}.gguf"
    
    # Check disk space (assume input size ~ output size)
    local input_size input_mb
    input_size=$(stat -f%z "$input" 2>/dev/null || stat -c%s "$input" 2>/dev/null || echo 0)
    input_mb=$((input_size / 1024 / 1024))
    
    local avail_mb
    avail_mb=$(df -m "$dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    
    if [ "$avail_mb" -lt "$((input_mb * 2))" ]; then
        error "Insufficient disk space: need ~$((input_mb * 2))MB, have ${avail_mb}MB"
        exit 1
    fi
    
    # Run quantization
    info "Quantizing: ${input}"
    info "  Type:   ${quant_type}"
    info "  Output: ${output}"
    echo ""
    
    "$quantize" "$input" "$output" "$quant_type" 2>&1 || {
        local exit_code=$?
        error "Quantization failed (exit code: ${exit_code})"
        return $exit_code
    }
    
    echo ""
    info "Quantization complete!"
    
    # Show output size
    if [ -f "$output" ]; then
        local out_size
        out_size=$(du -h "$output" | awk '{print $1}')
        info "Output size: ${out_size}"
        
        # Calculate compression ratio
        local ratio
        ratio=$(echo "scale=2; ${input_size} / $(stat -c%s "$output" 2>/dev/null || echo 1)" | bc 2>/dev/null || echo "?")
        info "Compression ratio: ${ratio}x"
    fi
    
    echo "$output"
}

# Main
main() {
    local cmd="${1:-}"

    case "$cmd" in
        check|--check)
            check_tool
            ;;
        list|--list|-l)
            echo "Available quantization types:"
            echo "  Q4_K_M  - 4-bit K-quant (medium)  — Good balance (default)"
            echo "  Q5_K_M  - 5-bit K-quant (medium)  — Higher quality"
            echo "  Q8_0    - 8-bit (fast)            — Near lossless"
            echo "  Q4_0    - 4-bit (standard)        — Smaller, lower quality"
            echo "  Q6_K    - 6-bit K-quant            — Better quality"
            echo "  Q3_K_M  - 3-bit K-quant (medium)  — Smaller, faster on CPU"
            echo "  Q2_K    - 2-bit K-quant            — Smallest, lowest quality"
            ;;
        --help|-h|"")
            echo "Usage:"
            echo "  $0 <input.gguf> [type]   Quantize model (default: Q4_K_M)"
            echo "  $0 check                 Check if quantize tool is available"
            echo "  $0 list                  List available quantization types"
            echo ""
            echo "Examples:"
            echo "  $0 qwen2.5-coder-1.5b-f16.gguf Q4_K_M"
            echo "  $0 qwen2.5-coder-3b-f16.gguf Q5_K_M"
            ;;
        *)
            if [ -n "$cmd" ]; then
                do_quantize "$cmd" "${2:-Q4_K_M}"
            else
                error "Usage: $0 <input.gguf> [type]"
                exit 1
            fi
            ;;
    esac
}

main "$@"
