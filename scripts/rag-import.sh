#!/bin/bash
# scripts/rag-import.sh — Index documents into RAG vector store
#
# Uses nomic-embed-text via Ollama API for embeddings
# Stores chunks + embeddings as JSON (sqlite3 upgrade path)
#
# Usage:
#   ./scripts/rag-import.sh /path/to/docs          # Index all .md/.txt files
#   ./scripts/rag-import.sh --update /path/to/docs  # Incremental update
#   ./scripts/rag-import.sh --clear                 # Clear all indexes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAG_DIR="${PROJECT_DIR}/rag-index"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Check prerequisites
check_prereqs() {
    if ! command -v curl &>/dev/null; then
        error "curl is required"
        exit 1
    fi
    # Check Ollama API is running
    if ! curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        error "Ollama API is not responding at localhost:11434"
        error "Start it with: ./scripts/start.sh"
        exit 1
    fi
    # Check nomic-embed-text is available
    if ! curl -s http://localhost:11434/api/tags | python3 -c "import json,sys; d=json.load(sys.stdin); models=[m['name'] for m in d.get('models',[])]; sys.exit(0 if any('nomic' in m for m in models) else 1)" 2>/dev/null; then
        warn "nomic-embed-text not found in Ollama. Pulling..."
        ollama pull nomic-embed-text
    fi
}

# The actual indexing is done by a Python script
run_indexer() {
    local docs_dir="$1"
    local update_mode="${2:-false}"

    if [ ! -d "$docs_dir" ]; then
        error "Directory not found: ${docs_dir}"
        exit 1
    fi

    mkdir -p "$RAG_DIR"

    python3 - "$docs_dir" "$RAG_DIR" "$update_mode" <<'PYEOF'
import json, os, sys, hashlib, re, math, time, urllib.request, urllib.error

docs_dir = sys.argv[1]
rag_dir = sys.argv[2]
update_mode = sys.argv[3].lower() == 'true'

OLLAMA_URL = "http://localhost:11434/api/embeddings"
MODEL = "nomic-embed-text"
CHUNK_SIZE = 2000    # ~500 tokens (4 chars/token)
CHUNK_OVERLAP = 512  # ~128 tokens overlap

def get_embedding(text):
    """Get embedding from Ollama API"""
    data = json.dumps({"model": MODEL, "prompt": text}).encode()
    req = urllib.request.Request(OLLAMA_URL, data=data,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            return result.get("embedding", [])
    except Exception as e:
        print(f"  [ERROR] Embedding failed: {e}", file=sys.stderr)
        return None

def chunk_text(text, source, metadata):
    """Split text into overlapping chunks"""
    chunks = []
    # Clean text
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = text.strip()
    
    if not text:
        return chunks
    
    start = 0
    chunk_id = 0
    while start < len(text):
        end = min(start + CHUNK_SIZE, len(text))
        
        # Try to break at paragraph or sentence boundary
        if end < len(text):
            # Look for paragraph break
            paragraph_break = text.rfind('\n\n', start, end)
            if paragraph_break > start + CHUNK_SIZE // 2:
                end = paragraph_break + 1
            else:
                # Look for sentence break
                sentence_break = max(
                    text.rfind('. ', start, end),
                    text.rfind('.\n', start, end),
                    text.rfind('?\n', start, end),
                    text.rfind('!\n', start, end)
                )
                if sentence_break > start + CHUNK_SIZE // 2:
                    end = sentence_break + 1
        
        chunk_text = text[start:end].strip()
        if chunk_text:
            chunk_id += 1
            chunk_hash = hashlib.md5(chunk_text.encode()).hexdigest()[:8]
            chunks.append({
                "id": f"{source}#{chunk_id}-{chunk_hash}",
                "text": chunk_text,
                "source": source,
                "metadata": metadata,
                "chunk_index": chunk_id,
                "char_start": start,
                "char_end": end
            })
        
        # Move with overlap
        next_start = end - CHUNK_OVERLAP
        if next_start <= start:
            next_start = end
        start = next_start
        
        if chunk_id > 200:
            break  # Safety limit
    
    return chunks

def load_index(index_path):
    """Load existing index if available"""
    if os.path.exists(index_path) and update_mode:
        with open(index_path, 'r') as f:
            return json.load(f)
    return []

def save_index(index_path, entries):
    with open(index_path, 'w') as f:
        json.dump(entries, f, indent=2)
    print(f"  Saved {len(entries)} chunks to {os.path.basename(index_path)}")

def file_hash(filepath):
    """Get a quick hash of file content for change detection"""
    h = hashlib.md5()
    with open(filepath, 'rb') as f:
        h.update(f.read())
    return h.hexdigest()

def needs_update(filepath, existing_entries):
    """Check if a file needs re-indexing based on hash"""
    if not update_mode:
        return True
    source = os.path.basename(filepath)
    current_hash = file_hash(filepath)
    for entry in existing_entries:
        if entry.get("source") == source:
            stored_hash = entry.get("metadata", {}).get("file_hash", "")
            if stored_hash == current_hash:
                return False
    return True

# Helper function for glob
def glob(base_dir, pattern):
    """Simple glob by extension"""
    import pathlib
    p = pathlib.Path(base_dir)
    ext = pattern.lstrip('*')
    return [str(f) for f in p.rglob(f'*{ext}') if f.is_file()]

# Main indexing logic
index_name = os.path.basename(docs_dir.rstrip('/'))
index_path = os.path.join(rag_dir, f"{index_name}.json")

print(f"Indexing documents from: {docs_dir}")
print(f"Index: {index_name}")
print(f"Mode: {'incremental' if update_mode else 'full'}")
print()

# Collect files
files = []
for ext in ('*.md', '*.txt', '*.rst'):
    files.extend([f for f in sorted(glob(docs_dir, ext))])

if not files:
    print("No .md, .txt, or .rst files found.")
    sys.exit(0)

print(f"Found {len(files)} files to process")

# Load existing index for incremental update
existing_entries = load_index(index_path)

# Keep entries for files that haven't changed (incremental mode)
kept_entries = []
if update_mode:
    for entry in existing_entries:
        src = entry.get("source", "")
        src_path = os.path.join(docs_dir, src)
        if os.path.exists(src_path) and not needs_update(src_path, existing_entries):
            kept_entries.append(entry)

if kept_entries:
    print(f"  Keeping {len(kept_entries)} chunks from unchanged files")

# Process each file
new_entries = []
total_files = len(files)

for idx, filepath in enumerate(files, 1):
    source = os.path.basename(filepath)
    print(f"[{idx}/{total_files}] {source}...", end=" ", flush=True)
    
    if not needs_update(filepath, existing_entries):
        print("unchanged, skipped")
        continue
    
    try:
        with open(filepath, 'r') as f:
            content = f.read()
    except Exception as e:
        print(f"ERROR: {e}")
        continue
    
    metadata = {
        "file_path": filepath,
        "file_hash": file_hash(filepath),
        "file_size": len(content),
        "indexed_at": time.strftime("%Y-%m-%dT%H:%M:%S")
    }
    
    chunks = chunk_text(content, source, metadata)
    
    if not chunks:
        print("no content")
        continue
    
    # Get embeddings for each chunk
    embedded_count = 0
    for i, chunk in enumerate(chunks):
        print(".", end="", flush=True)
        embedding = get_embedding(chunk["text"])
        if embedding:
            chunk["embedding"] = embedding
            embedded_count += 1
        else:
            chunk["embedding"] = []
        
        # Delay to avoid overwhelming Ollama
        if i < len(chunks) - 1:
            time.sleep(0.1)
    
    new_entries.extend(chunks)
    print(f" {embedded_count}/{len(chunks)} chunks embedded")
    
    # Batch save every 5 files
    if idx % 5 == 0 and new_entries:
        all_entries = kept_entries + new_entries
        save_index(index_path, all_entries)

# Final save
all_entries = kept_entries + new_entries
save_index(index_path, all_entries)

print()
print(f"Indexing complete:")
print(f"  Files processed: {len(files)}")
print(f"  Total chunks:   {len(all_entries)}")
print(f"  New chunks:     {len(new_entries)}")
print(f"  Kept chunks:    {len(kept_entries)}")

PYEOF
}

# Main
main() {
    local cmd="${1:-}"

    case "${cmd}" in
        --clear|-c)
            if [ -d "$RAG_DIR" ]; then
                rm -rf "${RAG_DIR:?}/"*
                info "All indexes cleared from ${RAG_DIR}"
            else
                info "No indexes to clear"
            fi
            ;;
        --update|-u)
            local dir="${2:-}"
            if [ -z "$dir" ]; then
                error "Usage: $0 --update /path/to/docs"
                exit 1
            fi
            check_prereqs
            run_indexer "$dir" true
            ;;
        --help|-h)
            echo "Usage:"
            echo "  $0 /path/to/docs           Index documents"
            echo "  $0 --update /path/to/docs   Incremental update"
            echo "  $0 --clear                  Clear all indexes"
            echo ""
            echo "Indexes are stored in: ${RAG_DIR}/"
            ;;
        "")
            error "Usage: $0 /path/to/docs | --update /path | --clear | --help"
            exit 1
            ;;
        *)
            # Assume it's a directory path
            if [ -d "$cmd" ]; then
                check_prereqs
                run_indexer "$cmd" false
            else
                error "Unknown option or directory not found: ${cmd}"
                exit 1
            fi
            ;;
    esac
}

main "$@"
