#!/bin/bash
# scripts/llama.cpp-serve.sh — Serve model via llama.cpp server (Vulkan/ROCm)
# Usage:
#   ./scripts/llama.cpp-serve.sh                    # Serve default model
#   ./scripts/llama.cpp-serve.sh <model.gguf>       # Serve specific model
#   ./scripts/llama.cpp-serve.sh --stop             # Stop llama-server
#   ./scripts/llama.cpp-serve.sh --status           # Check server status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
MODELS_DIR="${HOME}/.local/share/llama.cpp/models"
LLAMA_LIB_DIR="$(find "${HOME}/.local/llama.cpp/" -maxdepth 2 -name "*.so" -exec dirname {} \; 2>/dev/null | head -1)"

# Default model
DEFAULT_MODEL="${MODELS_DIR}/qwen2.5-coder-1.5b-q4_k_m.gguf"
PORT=11434
HOST="127.0.0.1"
NGL=${NGL:-999}   # Offload all layers to GPU
CTX=${CTX:-4096}   # Context size

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- Find llama-server ----
find_server() {
    if command -v llama-server &>/dev/null; then
        echo "$(command -v llama-server)"
    elif [ -f "${BIN_DIR}/llama-server" ]; then
        echo "${BIN_DIR}/llama-server"
    else
        return 1
    fi
}

# ---- Build library path ----
build_ld_path() {
    local lib_paths=()
    if [ -n "$LLAMA_LIB_DIR" ]; then
        lib_paths+=("$LLAMA_LIB_DIR")
    fi
    # Add common Vulkan library locations
    lib_paths+=("/usr/lib64")
    lib_paths+=("/usr/lib")
    lib_paths+=("/usr/local/lib")

    local path=""
    for p in "${lib_paths[@]}"; do
        if [ -d "$p" ] && ls "$p"/libvulkan* >/dev/null 2>&1; then
            [ -n "$path" ] && path="${path}:"
            path="${path}${p}"
        fi
    done
    echo "$path"
}

# ---- Start server ----
start_server() {
    local model="${1:-$DEFAULT_MODEL}"
    local server_cmd

    server_cmd=$(find_server) || {
        error "llama-server not found. Run scripts/llama.cpp-build.sh first."
        exit 1
    }

    # Check if already running
    if pgrep -f "llama-server" > /dev/null 2>&1; then
        PID=$(pgrep -f "llama-server")
        info "llama-server already running (pid ${PID})"
        echo "  Listening: http://${HOST}:${PORT}"
        echo "  To stop:  $0 --stop"
        return 0
    fi

    # Verify model exists
    if [ ! -f "$model" ]; then
        error "Model not found: ${model}"
        echo "  Download one first:"
        echo "    wget -O ${MODELS_DIR}/qwen2.5-coder-1.5b-q4_k_m.gguf \\"
        echo "      'https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf'"
        exit 1
    fi

    # Set library path for GPU backends
    LD_PATH=$(build_ld_path)
    export LD_LIBRARY_PATH="${LD_PATH}:${LD_LIBRARY_PATH:-}"

    info "Starting llama-server..."
    info "  Model:  ${model}"
    info "  GPU layers: ${NGL}"
    info "  Port:   ${PORT}"
    info "  Log:    /tmp/llama-server.log"

    # Detect GPU backend from binary info
    if ldd "$server_cmd" 2>/dev/null | grep -q libggml-vulkan; then
        info "  Backend: Vulkan"
    fi

    LD_LIBRARY_PATH="${LD_PATH}" nohup "$server_cmd" \
        -m "$model" \
        --host "$HOST" \
        --port "$PORT" \
        -ngl "$NGL" \
        -c "$CTX" \
        --log-file /tmp/llama-server.log \
        > /tmp/llama-server.stdout 2>&1 &

    local pid=$!
    echo "  PID: ${pid}"

    # Wait for server to be ready
    for i in $(seq 1 30); do
        if curl -s "http://${HOST}:${PORT}/health" > /dev/null 2>&1; then
            echo ""
            info "llama-server is ready!"
            echo "  API: http://${HOST}:${PORT}"
            echo "  Test: curl http://${HOST}:${PORT}/v1/completions -d '{
            \"prompt\": \"Hello\",
            \"n_predict\": 64
          }'"
            return 0
        fi
        sleep 1
    done

    error "llama-server failed to start in 30s. Check logs:"
    tail -20 /tmp/llama-server.log
    return 1
}

# ---- Stop server ----
stop_server() {
    local pid
    pid=$(pgrep -f "llama-server" 2>/dev/null || true)
    if [ -n "$pid" ]; then
        info "Stopping llama-server (pid ${pid})..."
        kill -TERM "$pid" 2>/dev/null || true
        for i in $(seq 1 10); do
            if ! pgrep -f "llama-server" > /dev/null 2>&1; then
                info "llama-server stopped."
                return 0
            fi
            sleep 1
        done
        # Force kill
        kill -KILL "$pid" 2>/dev/null || true
        info "llama-server force-stopped."
    else
        info "llama-server is not running."
    fi
}

# ---- Status ----
show_status() {
    local pid
    pid=$(pgrep -f "llama-server" 2>/dev/null || true)
    if [ -n "$pid" ]; then
        echo "llama-server: RUNNING (pid ${pid})"
        echo "  Port: http://${HOST}:${PORT}"
        if curl -s "http://${HOST}:${PORT}/health" > /dev/null 2>&1; then
            echo "  Health: OK"
        else
            echo "  Health: Not responding"
        fi
        echo ""
        echo "Recent log lines:"
        tail -5 /tmp/llama-server.log 2>/dev/null || echo "  (no log)"
    else
        echo "llama-server: NOT RUNNING"
        echo "  To start: $0 [model-path]"
    fi
}

# ---- Main ----
case "${1:-}" in
    --stop)
        stop_server
        ;;
    --status|status)
        show_status
        ;;
    --help|-h)
        echo "Usage: $0 [model-path|--stop|--status]"
        echo ""
        echo "  (no args)        Start llama-server with default model"
        echo "  <model.gguf>     Start with specific model"
        echo "  --stop           Stop running server"
        echo "  --status         Check server status"
        echo ""
        echo "Environment variables:"
        echo "  NGL    GPU layers to offload (default: 999 = all)"
        echo "  CTX    Context size (default: 4096)"
        echo "  PORT   Server port (default: 11434)"
        ;;
    *)
        start_server "${1:-}"
        ;;
esac
