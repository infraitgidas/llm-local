#!/bin/bash
# scripts/stop.sh — Stop Ollama server gracefully
# Usage: ./scripts/stop.sh

set -euo pipefail

PID=$(pgrep -x ollama 2>/dev/null) || {
    echo "ollama is not running"
    exit 0
}

echo "Stopping ollama (pid $PID)..."
kill -TERM "$PID"

# Wait up to 10 seconds for graceful shutdown
for i in $(seq 1 10); do
    if ! pgrep -x ollama > /dev/null 2>&1; then
        echo "ollama stopped"
        exit 0
    fi
    sleep 1
done

# Force kill if still running
echo "Forcing stop..."
kill -KILL "$PID" 2>/dev/null || true
echo "ollama force-stopped"
