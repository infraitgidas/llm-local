#!/bin/bash
# scripts/switch-model.sh — Switch active model in Ollama
# Usage: ./scripts/switch-model.sh <model-name>
#        ./scripts/switch-model.sh list

set -euo pipefail

show_models() {
    echo "Available models:"
    ollama list 2>/dev/null || echo "  (ollama not running or no models)"
}

if [ "${1:-}" = "list" ]; then
    show_models
    exit 0
fi

MODEL="${1:-}"

if [ -z "$MODEL" ]; then
    echo "Usage: $0 <model-name>"
    echo "       $0 list"
    echo ""
    show_models
    exit 1
fi

# Check if model exists
if ! ollama list 2>/dev/null | grep -q "^$MODEL\s"; then
    echo "Model '$MODEL' not found locally."
    echo "Pull it first: ollama pull $MODEL"
    show_models
    exit 1
fi

# Test the model by sending a simple prompt
echo "Switching to model: $MODEL"
echo "Testing model response..."
RESPONSE=$(ollama run "$MODEL" "Respond with OK if you are working." 2>&1)
echo "Model response: $RESPONSE"
echo ""
echo "Model '$MODEL' is active and responding."
