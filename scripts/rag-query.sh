#!/bin/bash
# scripts/rag-query.sh — Query the RAG vector store for relevant passages
#
# Takes a natural language query, finds relevant chunks via cosine similarity,
# and returns top-k results with source citations.
#
# Usage:
#   ./scripts/rag-query.sh "how to create a VM with 2 cores"
#   ./scripts/rag-query.sh --index proxmox "backup configuration"
#   ./scripts/rag-query.sh --index proxmox --raw "query"  # JSON output
#   ./scripts/rag-query.sh --list-indexes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAG_DIR="${PROJECT_DIR}/rag-index"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# The query logic in Python
run_query() {
    local query="$1"
    local index_name="$2"
    local raw_output="${3:-false}"

    python3 <<'PYEOF'
import json, math, sys, urllib.request, urllib.error, os

query = sys.argv[1]
index_name = sys.argv[2]
rag_dir = sys.argv[3]
raw_output = sys.argv[4].lower() == 'true'

OLLAMA_URL = "http://localhost:11434/api/embeddings"
MODEL = "nomic-embed-text"
TOP_K = 3

def get_embedding(text):
    """Get embedding from Ollama API"""
    data = json.dumps({"model": MODEL, "prompt": text}).encode()
    req = urllib.request.Request(OLLAMA_URL, data=data,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            emb = result.get("embedding", [])
            if not emb:
                print("[ERROR] Empty embedding returned", file=sys.stderr)
            return emb
    except Exception as e:
        print(f"[ERROR] Embedding query failed: {e}", file=sys.stderr)
        return None

def cosine_similarity(a, b):
    """Compute cosine similarity between two vectors"""
    if not a or not b:
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)

def load_index(index_path):
    if os.path.exists(index_path):
        with open(index_path, 'r') as f:
            return json.load(f)
    return []

# Find index file
index_path = os.path.join(rag_dir, f"{index_name}.json")
if not os.path.exists(index_path):
    # Try without .json
    if os.path.exists(os.path.join(rag_dir, index_name)):
        index_path = os.path.join(rag_dir, index_name)
    else:
        print(f"[ERROR] Index not found: {index_name}", file=sys.stderr)
        print(f"  Searched: {index_path}", file=sys.stderr)
        print(f"  Available indexes:", file=sys.stderr)
        for f in sorted(os.listdir(rag_dir)):
            print(f"    - {f}", file=sys.stderr)
        sys.exit(1)

entries = load_index(index_path)
if not entries:
    print("[ERROR] Index is empty")
    sys.exit(1)

# Get query embedding
print(f"[INFO] Query: {query[:80]}...", file=sys.stderr)
query_emb = get_embedding(query)
if not query_emb:
    sys.exit(1)

# Score all entries
scored = []
for entry in entries:
    emb = entry.get("embedding", [])
    if emb:
        score = cosine_similarity(query_emb, emb)
        scored.append((score, entry))

scored.sort(key=lambda x: x[0], reverse=True)

# Return top-k
top_k = scored[:TOP_K]

if raw_output:
    results = []
    for score, entry in top_k:
        results.append({
            "score": round(score, 4),
            "source": entry.get("source", "unknown"),
            "text": entry.get("text", "")[:500],
            "metadata": entry.get("metadata", {})
        })
    print(json.dumps({
        "query": query,
        "results": results,
        "total_chunks": len(entries)
    }, indent=2))
else:
    if not top_k:
        print("=" * 60)
        print(" No relevant documentation found.")
        print(" Try rephrasing your query or indexing more documents.")
        print("=" * 60)
    else:
        print()
        print("=" * 60)
        print(f" TOP {len(top_k)} RELEVANT PASSAGES")
        print(f" Query: {query[:80]}{'...' if len(query) > 80 else ''}")
        print(f" Search over {len(entries)} chunks")
        print("=" * 60)
        print()
        
        for i, (score, entry) in enumerate(top_k, 1):
            source = entry.get("source", "unknown")
            text = entry.get("text", "")
            # Truncate display text
            display_text = text[:600]
            if len(text) > 600:
                display_text += "..."
            
            print(f"--- Result #{i} (score: {score:.3f}) ---")
            print(f"  Source: {source}")
            chunk_idx = entry.get("chunk_index", "?")
            print(f"  Chunk:  #{chunk_idx}")
            print(f"  {'─' * 50}")
            print(f"{display_text}")
            print()

PYEOF "$query" "$index_name" "$RAG_DIR" "$raw_output"
}

list_indexes() {
    if [ ! -d "$RAG_DIR" ]; then
        info "No indexes found (${RAG_DIR} does not exist)"
        return
    fi
    local count=0
    for f in "$RAG_DIR"/*.json; do
        if [ -f "$f" ]; then
            local name
            name=$(basename "$f" .json)
            local chunks
            chunks=$(python3 -c "import json; print(len(json.load(open('$f'))))" 2>/dev/null || echo "?")
            echo "  ${name}: ${chunks} chunks"
            count=$((count + 1))
        fi
    done
    if [ "$count" -eq 0 ]; then
        info "No indexes found"
    fi
}

# Main
main() {
    local index_name=""
    local raw_output=false
    local query=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --index|-i)
                index_name="$2"
                shift 2
                ;;
            --raw|-r)
                raw_output=true
                shift
                ;;
            --list-indexes|-l)
                list_indexes
                exit 0
                ;;
            --help|-h)
                echo "Usage:"
                echo "  $0 [--index <name>] \"<query>\""
                echo "  $0 --index proxmox \"how to create a VM\""
                echo "  $0 --index proxmox --raw \"query\"    # JSON output"
                echo "  $0 --list-indexes"
                echo ""
                echo "Default index: auto-detect from available indexes"
                exit 0
                ;;
            *)
                query="$1"
                shift
                ;;
        esac
    done

    if [ -z "$query" ]; then
        error "Usage: $0 [--index <name>] \"<query>\""
        echo "  Use --help for details"
        exit 1
    fi

    # Auto-detect index if not specified
    if [ -z "$index_name" ]; then
        if [ -d "$RAG_DIR" ]; then
            local indexes=("$RAG_DIR"/*.json)
            if [ ${#indexes[@]} -eq 1 ] && [ -f "${indexes[0]}" ]; then
                index_name=$(basename "${indexes[0]}" .json)
                info "Auto-selected index: ${index_name}"
            elif [ ${#indexes[@]} -gt 1 ]; then
                error "Multiple indexes found. Specify with --index:"
                list_indexes
                exit 1
            else
                error "No indexes found. Run scripts/rag-import.sh first."
                exit 1
            fi
        else
            error "No indexes found. Run scripts/rag-import.sh first."
            exit 1
        fi
    fi

    run_query "$query" "$index_name" "$raw_output"
}

main "$@"
