#!/bin/bash
# scripts/llama.cpp-build.sh — Download pre-built llama.cpp with Vulkan
# Supports: Vulkan (default) or ROCm/HIP if available
#
# Usage:
#   ./scripts/llama.cpp-build.sh            # Download pre-built Vulkan binaries
#   ./scripts/llama.cpp-build.sh --rocm     # Build from source with ROCm
#   ./scripts/llama.cpp-build.sh --vulkan   # Build from source with Vulkan (needs cmake + Vulkan SDK)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="${HOME}/.local/llama.cpp"
BIN_DIR="${HOME}/.local/bin"
MODELS_DIR="${HOME}/.local/share/llama.cpp/models"
LLAMA_VERSION="b9596"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- Detect GPU Backend ----
detect_backend() {
    # Check for ROCm/HIP
    if command -v hipcc &>/dev/null; then
        echo "rocm"
        return
    fi
    # Check for Vulkan loader
    if ldconfig -p 2>/dev/null | grep -q libvulkan; then
        echo "vulkan"
        return
    fi
    echo "cpu"
}

# ---- Download pre-built Vulkan binaries ----
download_prebuilt() {
    info "Downloading pre-built llama.cpp ${LLAMA_VERSION} (Vulkan)..."
    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$MODELS_DIR"

    local url="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}/llama-${LLAMA_VERSION}-bin-ubuntu-vulkan-x64.tar.gz"
    local tarball="/tmp/llama-${LLAMA_VERSION}-vulkan.tar.gz"

    if command -v curl &>/dev/null; then
        curl -#L -o "$tarball" "$url"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress -O "$tarball" "$url"
    else
        error "Neither curl nor wget found. Install one of them."
        exit 1
    fi

    info "Extracting to ${INSTALL_DIR}..."
    tar xzf "$tarball" -C "$INSTALL_DIR/"

    # Create symlinks
    local extracted_dir
    extracted_dir=$(find "$INSTALL_DIR" -maxdepth 1 -type d -name "llama-*" | head -1)
    if [ -z "$extracted_dir" ]; then
        extracted_dir="$INSTALL_DIR"
    fi

    for bin in llama-server llama-cli llama-bench; do
        if [ -f "$extracted_dir/$bin" ]; then
            ln -sf "$extracted_dir/$bin" "$BIN_DIR/$bin"
            chmod +x "$BIN_DIR/$bin"
        fi
    done

    # Create library path helper
    mkdir -p "$extracted_dir"
    echo "export LD_LIBRARY_PATH=\"${extracted_dir}:\$LD_LIBRARY_PATH\"" \
        > "${INSTALL_DIR}/env.sh"

    rm -f "$tarball"
    info "llama.cpp ${LLAMA_VERSION} installed to ${extracted_dir}"
}

# ---- Build from source with Vulkan ----
build_vulkan() {
    info "Building llama.cpp from source with Vulkan..."
    if ! command -v cmake &>/dev/null; then
        error "cmake is required. Install it or use pre-built binaries."
        exit 1
    fi

    local build_dir="/tmp/llama.cpp-build"
    mkdir -p "$build_dir"

    cd "$build_dir"
    if [ ! -d "llama.cpp" ]; then
        git clone --depth 1 https://github.com/ggml-org/llama.cpp.git
    fi

    cd llama.cpp
    mkdir -p build && cd build
    cmake .. -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
    cmake --build . --config Release -j "$(nproc)"

    # Copy binaries
    mkdir -p "$INSTALL_DIR"
    cp -r bin/* "$INSTALL_DIR/" 2>/dev/null || true
    cp -r src/*.so "$INSTALL_DIR/" 2>/dev/null || true

    info "llama.cpp built from source with Vulkan"
}

# ---- Build from source with ROCm ----
build_rocm() {
    info "Building llama.cpp from source with ROCm..."
    if ! command -v cmake &>/dev/null; then
        error "cmake is required."
        exit 1
    fi
    if ! command -v hipcc &>/dev/null; then
        error "hipcc not found. Install ROCm/HIP first."
        exit 1
    fi

    local build_dir="/tmp/llama.cpp-build"
    mkdir -p "$build_dir"

    cd "$build_dir"
    if [ ! -d "llama.cpp" ]; then
        git clone --depth 1 https://github.com/ggml-org/llama.cpp.git
    fi

    cd llama.cpp
    mkdir -p build && cd build
    cmake .. -DGGML_HIPBLAS=ON \
             -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_C_COMPILER=hipcc \
             -DCMAKE_CXX_COMPILER=hipcc \
             -DAMDGPU_TARGETS=gfx803
    cmake --build . --config Release -j "$(nproc)"

    mkdir -p "$INSTALL_DIR"
    cp -r bin/* "$INSTALL_DIR/" 2>/dev/null || true
    cp -r src/*.so "$INSTALL_DIR/" 2>/dev/null || true

    info "llama.cpp built from source with ROCm/HIP for gfx803"
}

# ---- Main ----
main() {
    local backend
    backend=$(detect_backend)
    local mode="${1:-auto}"

    echo "========================================"
    echo "  llama.cpp Build Script"
    echo "  Backend detected: ${backend}"
    echo "========================================"
    echo ""

    case "$mode" in
        --rocm)
            if [ "$backend" != "rocm" ]; then
                warn "ROCm not detected. Attempting build anyway..."
            fi
            build_rocm
            ;;
        --vulkan)
            if [ "$backend" != "vulkan" ] && [ "$backend" != "rocm" ]; then
                warn "No GPU backend detected. Building for CPU-only will fail..."
            fi
            build_vulkan
            ;;
        --source)
            build_vulkan
            ;;
        *)
            download_prebuilt
            ;;
    esac

    # Verify installation
    if [ -f "$BIN_DIR/llama-server" ]; then
        echo ""
        info "llama.cpp installed successfully!"
        echo "  Binaries: ${BIN_DIR}/llama-*"
        echo "  Models:   ${MODELS_DIR}/"
        echo ""
        echo "  Quick test:"
        echo "    LLAMA_LIBRARY_PATH=\${HOME}/.local/llama.cpp/llama-${LLAMA_VERSION} llama-cli \\"
        echo "      -m \${MODELS_DIR}/qwen2.5-coder-1.5b-q4_k_m.gguf \\"
        echo "      -ngl 999 -p 'Hello' -n 128"
    fi
}

main "$@"
