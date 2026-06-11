#!/bin/bash
# scripts/status.sh — Show Ollama server status
# Usage: ./scripts/status.sh

set -euo pipefail

if PID=$(pgrep -x ollama 2>/dev/null); then
    echo "ollama: RUNNING (pid $PID)"
    echo ""
    echo "Models available:"
    ollama list 2>/dev/null || echo "  (unable to list models)"
    echo ""
    echo "API status:"
    curl -s http://localhost:11434/api/tags 2>/dev/null \
        | python3 -m json.tool 2>/dev/null \
        || echo "  API not responding at localhost:11434"
else
    echo "ollama: NOT RUNNING"
    echo ""
    echo "To start: ./scripts/start.sh"
fi

echo ""
echo "Memory usage:"
free -h | grep -E "Mem:|Swap:"
