#!/bin/bash
# scripts/model-download.sh — Download GGUF models with resume support
#
# Supports:
#   ollama pull <name>        — Pull model via Ollama (built-in verification)
#   gguf <url> [output] [sha256sum] — Download GGUF with resume via curl
#
# Usage:
#   ./scripts/model-download.sh ollama qwen2.5-coder:3b
#   ./scripts/model-download.sh gguf https://example.com/model.gguf models/model.gguf
#   ./scripts/model-download.sh gguf https://example.com/model.gguf models/model.gguf <sha256>
#   ./scripts/model-download.sh list
#   ./scripts/model-download.sh disk   # Check available disk space

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODELS_DIR="${PROJECT_DIR}/models"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

check_disk() {
    local needed="${1:-2}"  # Default 2GB minimum
    local avail
    avail=$(df -BG "$MODELS_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")
    if [ "$avail" -lt "$needed" ]; then
        error "Insufficient disk space: ${avail}GB available, ${needed}GB needed"
        return 1
    fi
    info "Disk space OK: ${avail}GB available"
}

# Verify SHA256 checksum of a file
verify_checksum() {
    local file="$1"
    local expected="$2"
    if [ -z "$expected" ]; then
        warn "No checksum provided — skipping verification"
        return 0
    fi
    info "Verifying checksum..."
    local actual
    actual=$(sha256sum "$file" | awk '{print $1}')
    if [ "$actual" = "$expected" ]; then
        info "Checksum VERIFIED: ${actual}"
        return 0
    else
        error "Checksum MISMATCH"
        echo "  Expected: ${expected}"
        echo "  Actual:   ${actual}"
        return 1
    fi
}

# Download GGUF with resume support
download_gguf() {
    local url="$1"
    local output="$2"
    local checksum="${3:-}"

    mkdir -p "$MODELS_DIR"

    # Resolve output path
    if [ -z "$output" ]; then
        output="${MODELS_DIR}/$(basename "$url")"
    elif [[ "$output" != /* ]]; then
        output="${MODELS_DIR}/${output}"
    fi

    # Check disk (assume file ~2GB)
    check_disk 2 || return 1

    # Check if already fully downloaded (checksum match)
    if [ -f "$output" ] && [ -n "$checksum" ]; then
        if verify_checksum "$output" "$checksum" 2>/dev/null; then
            info "File already downloaded and verified: ${output}"
            du -h "$output" | awk '{print "  Size: "$1}'
            echo "$output"
            return 0
        fi
    fi

    info "Downloading: ${url}"
    info "Target:      ${output}"
    info "Starting download (resume supported)..."

    # Download with resume support
    curl -L -C - -o "$output" "$url" --progress-bar 2>&1 || {
        local exit_code=$?
        if [ -f "$output" ]; then
            warn "Download interrupted at $(du -h "$output" | awk '{print $1}')"
            warn "Re-run to resume from where it left off"
        fi
        return $exit_code
    }

    echo ""
    info "Download complete!"
    du -h "$output" | awk '{print "  Size: "$1}'

    # Verify checksum
    if [ -n "$checksum" ]; then
        verify_checksum "$output" "$checksum"
    fi

    echo "$output"
}

# Pull via Ollama
pull_ollama() {
    local model="${1:-}"
    if [ -z "$model" ]; then
        error "Usage: $0 ollama <model-name>"
        return 1
    fi

    # Check disk (Ollama stores in ~/.ollama, assume 3GB needed)
    check_disk 3 || return 1

    info "Pulling ${model} via Ollama..."
    ollama pull "$model" 2>&1 || {
        error "Failed to pull ${model}"
        return 1
    }

    info "Model '${model}' pulled successfully"
    ollama show "$model" 2>/dev/null || true
}

# List models
list_models() {
    header "Models Directory (${MODELS_DIR})"
    if [ -d "$MODELS_DIR" ] && [ "$(ls -A "$MODELS_DIR" 2>/dev/null)" ]; then
        ls -lh "$MODELS_DIR" | awk 'NR>1 {print "  " $0}'
    else
        echo "  (empty)"
    fi

    echo ""
    header "Ollama Models"
    if command -v ollama &>/dev/null; then
        ollama list 2>/dev/null || echo "  (ollama not running)"
    else
        echo "  (ollama not installed)"
    fi
}

# Main
main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    case "$cmd" in
        ollama)
            pull_ollama "${1:-}"
            ;;
        gguf)
            download_gguf "${1:-}" "${2:-}" "${3:-}"
            ;;
        list|--list|-l)
            list_models
            ;;
        disk|--disk)
            check_disk "${1:-2}"
            ;;
        --help|-h|"")
            echo "Usage:"
            echo "  $0 ollama <model-name>          Pull model via Ollama"
            echo "  $0 gguf <url> [output] [sha256]  Download GGUF with resume"
            echo "  $0 list                          List all models"
            echo "  $0 disk [min-gb]                 Check available disk space"
            echo ""
            echo "Examples:"
            echo "  $0 ollama qwen2.5-coder:3b"
            echo "  $0 gguf https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf"
            ;;
        *)
            error "Unknown command: ${cmd}"
            echo "Usage: $0 ollama <name> | gguf <url> [output] [sha256] | list | disk"
            exit 1
            ;;
    esac
}

main "$@"
