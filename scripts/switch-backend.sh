#!/bin/bash
# scripts/switch-backend.sh — Switch between Ollama and llama.cpp backends
# The API endpoint remains at localhost:11434 for both backends.
#
# Usage:
#   ./scripts/switch-backend.sh           # Show current backend
#   ./scripts/switch-backend.sh ollama    # Switch to Ollama
#   ./scripts/switch-backend.sh llama     # Switch to llama.cpp
#   ./scripts/switch-backend.sh status    # Show backend status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
section() { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

# ---- Detect Backends ----

find_ollama_pid() {
    pgrep -x ollama 2>/dev/null || true
}

find_llama_pid() {
    pgrep -f "llama-server" 2>/dev/null || true
}

is_ollama_running() {
    [ -n "$(find_ollama_pid)" ]
}

is_llama_running() {
    [ -n "$(find_llama_pid)" ]
}

is_api_responding() {
    curl -s -o /dev/null -w "%{http_code}" http://localhost:11434/api/tags 2>/dev/null | grep -q "200"
}

detect_active_backend() {
    if is_llama_running; then
        echo "llama.cpp"
    elif is_ollama_running; then
        echo "ollama"
    else
        echo "none"
    fi
}

# ---- Status ----

show_status() {
    local backend
    backend=$(detect_active_backend)

    section "Backend Status"
    echo "Active backend: ${backend}"
    echo ""

    # Ollama
    if is_ollama_running; then
        local opid
        opid=$(find_ollama_pid)
        echo "  ollama:     RUNNING (pid ${opid})"
    else
        echo "  ollama:     STOPPED"
    fi

    # llama.cpp
    if is_llama_running; then
        local lpid
        lpid=$(find_llama_pid)
        echo "  llama.cpp:  RUNNING (pid ${lpid})"
    else
        echo "  llama.cpp:  STOPPED"
    fi

    # API
    if is_api_responding; then
        echo "  :11434 API: RESPONDING"
    else
        echo "  :11434 API: NOT RESPONDING"
    fi

    # Memory
    echo ""
    echo "Memory:"
    free -h | grep -E "Mem:|Swap:"
}

# ---- Switch to Ollama ----

switch_to_ollama() {
    section "Switching to Ollama"

    # Stop llama.cpp if running
    if is_llama_running; then
        local lpid
        lpid=$(find_llama_pid)
        info "Stopping llama.cpp (pid ${lpid})..."
        kill -TERM "$lpid" 2>/dev/null || true
        sleep 2
        if is_llama_running; then
            warn "llama.cpp didn't stop gracefully, forcing..."
            kill -KILL "$(find_llama_pid)" 2>/dev/null || true
            sleep 1
        fi
        info "llama.cpp stopped."
    fi

    # Start Ollama if not running
    if ! is_ollama_running; then
        info "Starting ollama..."
        ollama serve > /tmp/ollama.log 2>&1 &
        sleep 3
        if is_ollama_running; then
            info "ollama started (pid $(find_ollama_pid))."
        else
            error "Failed to start ollama."
            tail -5 /tmp/ollama.log
            return 1
        fi
    else
        info "ollama is already running."
    fi

    # Verify API
    for i in $(seq 1 10); do
        if is_api_responding; then
            info "Backend switch complete. API at :11434 is responding."
            echo "  Active backend: ollama"
            return 0
        fi
        sleep 1
    done

    warn "API :11434 is not responding yet."
    return 1
}

# ---- Switch to llama.cpp ----

switch_to_llama() {
    section "Switching to llama.cpp"

    # Stop Ollama if running
    if is_ollama_running; then
        local opid
        opid=$(find_ollama_pid)
        info "Stopping ollama (pid ${opid})..."
        kill -TERM "$opid" 2>/dev/null || true
        sleep 3
        if is_ollama_running; then
            warn "ollama didn't stop gracefully, forcing..."
            kill -KILL "$(find_ollama_pid)" 2>/dev/null || true
            sleep 1
        fi
        info "ollama stopped."
    fi

    # Start llama.cpp
    if ! is_llama_running; then
        if [ -f "${SCRIPT_DIR}/llama.cpp-serve.sh" ]; then
            info "Starting llama-server..."
            "${SCRIPT_DIR}/llama.cpp-serve.sh" || {
                error "Failed to start llama.cpp server."
                return 1
            }
        else
            # Direct start as fallback
            local server_cmd
            server_cmd=$(command -v llama-server 2>/dev/null || echo "${HOME}/.local/bin/llama-server")
            local model="${HOME}/.local/share/llama.cpp/models/qwen2.5-coder-1.5b-q4_k_m.gguf"
            local libdir
            libdir=$(find "${HOME}/.local/llama.cpp" -name "*.so" -exec dirname {} \; 2>/dev/null | head -1 || echo "")

            if [ ! -f "$server_cmd" ]; then
                error "llama-server not found. Run scripts/llama.cpp-build.sh first."
                return 1
            fi
            if [ ! -f "$model" ]; then
                error "Model not found: ${model}"
                return 1
            fi

            info "Starting llama-server directly..."
            if [ -n "$libdir" ]; then
                export LD_LIBRARY_PATH="${libdir}:/usr/lib64:${LD_LIBRARY_PATH:-}"
            fi

            nohup "$server_cmd" -m "$model" --host 127.0.0.1 --port 11434 \
                -ngl 999 -c 4096 > /tmp/llama-server.log 2>&1 &
            sleep 3
        fi
    else
        info "llama-server is already running."
    fi

    # Verify API
    for i in $(seq 1 15); do
        if curl -s http://localhost:11434/v1/completions \
            -d '{"prompt":"hi","n_predict":1,"stream":false}' \
            > /dev/null 2>&1; then
            info "Backend switch complete. API at :11434 is responding."
            echo "  Active backend: llama.cpp"
            return 0
        fi
        sleep 1
    done

    warn "API :11434 is not responding yet. Check logs:"
    tail -5 /tmp/llama-server.log 2>/dev/null || true
    return 1
}

# ---- Main ----

main() {
    local cmd="${1:-status}"

    case "$cmd" in
        status|--status)
            show_status
            ;;
        ollama|--ollama)
            switch_to_ollama
            ;;
        llama|llama.cpp|--llama|--llama.cpp)
            switch_to_llama
            ;;
        --help|-h)
            echo "Usage: $0 [ollama|llama|status]"
            echo ""
            echo "  $0               Show current backend status"
            echo "  $0 ollama        Switch to Ollama backend"
            echo "  $0 llama         Switch to llama.cpp backend"
            echo "  $0 status        Show backend status"
            echo ""
            echo "Both backends serve on localhost:11434 for API compatibility."
            ;;
        *)
            error "Unknown command: ${cmd}"
            echo "Usage: $0 [ollama|llama|status]"
            exit 1
            ;;
    esac
}

main "$@"
