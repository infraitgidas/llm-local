#!/bin/bash
# scripts/start.sh — Start Ollama server
# Usage: ./scripts/start.sh

set -euo pipefail

if pgrep -x ollama > /dev/null 2>&1; then
    echo "ollama is already running (pid $(pgrep -x ollama))"
    exit 0
fi

echo "Starting ollama server..."
ollama serve > /tmp/ollama.log 2>&1 &
sleep 2

if pgrep -x ollama > /dev/null 2>&1; then
    echo "ollama server started (pid $(pgrep -x ollama))"
else
    echo "ERROR: Failed to start ollama server"
    tail -5 /tmp/ollama.log
    exit 1
fi
