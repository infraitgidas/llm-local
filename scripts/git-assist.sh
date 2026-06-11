#!/bin/bash
# scripts/git-assist.sh — Generate conventional commit messages from diff
# Usage: git diff --cached | ./scripts/git-assist.sh
#        ./scripts/git-assist.sh < diff.txt
#        ./scripts/git-assist.sh --file diff.txt

set -euo pipefail

MODEL="${OLLAMA_MODEL:-qwen2.5-coder:1.5b}"
CONFIG_DIR="${HOME}/.config/llm-local"
SYSTEM_PROMPT_FILE="${CONFIG_DIR}/git-prompt.txt"

# Create config dir if needed
mkdir -p "$CONFIG_DIR"

# Generate system prompt if not cached
if [ ! -f "$SYSTEM_PROMPT_FILE" ]; then
    cat > "$SYSTEM_PROMPT_FILE" << 'EOPROMPT'
You are a git commit assistant. Your task is to generate concise, meaningful commit messages from diffs.

Rules:
- Use conventional commits format: type(scope): description
- Types: feat, fix, docs, style, refactor, perf, test, chore, ci
- Keep the subject line under 72 characters
- If the user writes in Spanish, respond in Spanish
- If the user writes in English, respond in English
- Include a brief body only if the change is non-trivial
- Do not include modifiers like "Co-Authored-By" or AI attribution
- Focus on WHAT and WHY, not HOW

Examples:
- feat(auth): add JWT token validation middleware
- fix(api): handle empty response in user list endpoint
- docs(readme): update installation instructions
- refactor(db): extract query builder to separate module
EOPROMPT
fi

# Read diff from stdin or file
if [ "${1:-}" = "--file" ]; then
    DIFF_FILE="${2:-}"
    if [ ! -f "$DIFF_FILE" ]; then
        echo "Error: file not found: $DIFF_FILE"
        exit 1
    fi
    DIFF=$(cat "$DIFF_FILE")
elif [ ! -t 0 ]; then
    DIFF=$(cat)
else
    echo "Usage: git diff --cached | $0"
    echo "       $0 --file <diff.txt>"
    exit 1
fi

if [ -z "$DIFF" ]; then
    echo "No diff provided. Stage changes first with 'git add'."
    exit 1
fi

# Build the prompt
PROMPT="Generate a conventional commit message for this diff:

\`\`\`diff
${DIFF}
\`\`\`

Respond with ONLY the commit message, nothing else."

# Call Ollama
echo "Generating commit message..."
echo ""
ollama run "$MODEL" "$PROMPT" 2>/dev/null
echo ""
