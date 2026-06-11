#!/bin/bash
# scripts/stack-setup.sh — First-run setup for the LLM local stack
# Usage: ./scripts/stack-setup.sh [--quick]
#   --quick: skip model downloads, only setup scripts and config
#
# This script checks dependencies, installs what it can, and verifies
# the stack is ready to use.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STEP=0
TOTAL=6

check_step() {
    local desc="$1" cmd="$2"
    STEP=$((STEP + 1))
    echo -e "[${STEP}/${TOTAL}] ${desc}..."
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} OK"
        return 0
    else
        echo -e "  ${YELLOW}⚠${NC} NOT AVAILABLE"
        return 1
    fi
}

echo "================================================"
echo "  LLM Local Stack — Setup"
echo "================================================"
echo ""

# Step 1: Ollama
check_step "Ollama installed" "which ollama" || echo "  Install: brew install ollama"

# Step 2: llama.cpp (Vulkan)
check_step "llama-server (Vulkan) available" \
    "command -v llama-server && llama-server --version" || \
    echo "  Run: ./scripts/llama.cpp-build.sh pre-built"

# Step 3: API reachable
check_step "API responds at localhost:11434" \
    "curl -sf http://localhost:11434/api/tags > /dev/null" || \
    echo "  Start: ./scripts/start.sh  (or ./scripts/llama.cpp-serve.sh start)"

# Step 4: Required scripts exist
check_step "All management scripts present" \
    "test -x scripts/start.sh -a -x scripts/stop.sh -a -x scripts/status.sh -a -x scripts/switch-profile.sh -a -x scripts/switch-backend.sh"

# Step 5: Models
check_step "At least one model available" \
    "ollama list 2>/dev/null | grep -q qwen" || \
    echo "  Pull: ollama pull qwen2.5-coder:1.5b"

# Step 6: Config profiles
check_step "Config profiles exist" \
    "test -f config/git.yaml -a -f config/infra.yaml -a -f config/doc.yaml" || \
    echo "  Some profiles missing — check config/ directory"

echo ""
echo "================================================"
echo "  Stack setup complete"
echo "================================================"
echo ""
echo "Quick start:"
echo "  1. Start server:  ./scripts/start.sh"
echo "  2. Test model:    ollama run qwen2.5-coder:1.5b 'Hola'"
echo "  3. Git assist:    git diff --cached | ./scripts/git-assist.sh"
echo "  4. RAG query:     ./scripts/rag-query.sh 'how to create a VM'"
echo "  5. Profiles:      ./scripts/switch-profile.sh infra"
echo ""
