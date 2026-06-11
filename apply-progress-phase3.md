# Apply Progress: Phase 3 — Multi-model + RAG (T10-T15)

## Change
`setup-local-inference-stack` — Fase 3 completada.

## Summary
Sexta tanda de implementación. Fase 3 completa: multi-modelo con 1.5B↔3B, pipeline RAG (nomic-embed + cosine similarity), perfiles de tarea (git, infra, doc, proxmox), y benchmark final.

## Completed Tasks

### T10 — model-download.sh + Qwen3B
- Created `scripts/model-download.sh` with resume support via `curl -C -`
- Modes: `ollama pull <name>` and `gguf <url> [checksum]`
- Disk space check, SHA256 verification, model listing
- Downloaded `qwen2.5-coder:3b` (1.9 GB, Q4_K_M) via Ollama
- Downloaded `nomic-embed-text` (274 MB) for RAG

### T11 — Config profiles
- `config/infra.yaml` — infra agent profile (3B, temp 0.2)
- `config/doc.yaml` — documentation profile (3B, temp 0.4)
- `config/proxmox.yaml` — Proxmox profile with RAG index (3B, temp 0.2)
- `config/system-prompts/infra-agent.md` — detailed system prompt for sysadmin/Proxmox
- `config/system-prompts/documentation.md` — detailed system prompt for technical writing

### T12 — RAG pipeline
- `scripts/rag-import.sh` — indexes .md/.txt files using nomic-embed-text via Ollama API
  - 512-token chunks with 128-token overlap (approximated as 2000/512 chars)
  - Incremental update support (file hash change detection)
  - JSON vector store (sqlite3 upgrade path per design)
- `scripts/rag-query.sh` — semantic search with cosine similarity
  - Top-3 relevant passages with source citations
  - `--raw` flag for JSON output, multi-index support, auto-detect

### T13 — Index docs + verify
- `docs/proxmox-basics.md` — VM/CT creation, storage, backup, network, cluster, admin
- `docs/infra-basics.md` — systemd, disk, LVM, network, bash scripting
- Indexed 2 files → 8 chunks in `rag-index/docs.json`
- Verified query "cómo crear una VM con 2 cores y 4GB RAM" → top result: `qm create 100 --cores 2 --memory 4096` (score 0.549)

### T14 — Profile switching, quantization, model registry
- `config/model-registry.yaml` — catalogs 1.5B, 3B, nomic-embed with VRAM/RAM estimates
- `scripts/switch-profile.sh` — reads config/<profile>.yaml, swaps model + temp + system prompt
  - Unload/load pattern to free VRAM, state tracking in `.openprofile`
  - Env vars (`LLM_PROFILE`, `LLM_MODEL`, etc.) for other scripts
  - Resource check, auto-list profiles
- `scripts/quantize.sh` — wraps llama-quantize with validation and disk checks

### T15 — Final benchmark
- Created `scripts/benchmark-final.sh` (comprehensive suite)
- Tested Ollama CPU 1.5B: avg 9.7 tok/s, 311ms TTFT
- Tested Ollama CPU 3B: avg 5.2 tok/s, 541ms TTFT
- Reference llama.cpp+Vulkan 1.5B: 85.28 tok/s (Phase 2)
- RAG: avg 170ms latency, 3/3 queries successful, avg score 0.616
- Memory: 75.7% RAM (within 85% constraint)
- VRAM: 10.6% (Ollama uses CPU, within 85% constraint)
- Results in `benchmark-results/final.json`

## Files Changed (this batch)

| File | Action | Description |
|------|--------|-------------|
| `scripts/model-download.sh` | Created | GGUF download with resume + Ollama pull |
| `config/infra.yaml` | Created | Infra agent profile |
| `config/doc.yaml` | Created | Documentation profile |
| `config/proxmox.yaml` | Created | Proxmox + RAG profile |
| `config/system-prompts/infra-agent.md` | Created | Sysadmin/Proxmox system prompt |
| `config/system-prompts/documentation.md` | Created | Technical writing system prompt |
| `scripts/rag-import.sh` | Created | Document indexing with nomic-embed |
| `scripts/rag-query.sh` | Created | Semantic search with cosine similarity |
| `docs/proxmox-basics.md` | Created | Proxmox reference documentation |
| `docs/infra-basics.md` | Created | Linux infrastructure reference |
| `scripts/switch-profile.sh` | Created | Profile-based model switching |
| `scripts/quantize.sh` | Created | GGUF quantization wrapper |
| `scripts/benchmark-final.sh` | Created | Comprehensive final benchmark |
| `config/model-registry.yaml` | Created | Model catalog with resources |
| `benchmark-results/final.json` | Created | Final benchmark results |
| `openspec/changes/.../tasks.md` | Updated | Marked T10-T15 complete |

## Deviations from Design
- **Vector store**: Used JSON instead of sqlite-vss — sqlite-vss requires C extension build. JSON is sufficient for current doc volume (8 chunks). sqlite3 upgrade path preserved.
- **3B access**: Downloaded via Ollama instead of GGUF to `models/` — Ollama provides built-in integrity verification and model management. `model-download.sh` supports both paths.
- **Q5_K_M vs Q4_K_M**: Downloaded Q4_K_M (Ollama default) instead of Q5_K_M — Q4_K_M uses ~1.8GB VRAM vs Q5_K_M's ~2.2GB, critical for 4GB RX 580.

## Issues Found
- Swap usage at 2.5GB (within total 11GB swap, but indicates memory pressure)
- 3B model only achieves 5.2 tok/s on Ollama CPU — recommend llama.cpp+Vulkan for production use
- RX 580 4GB VRAM cannot fit both 1.5B + 3B simultaneously — unload/load pattern verified

## Constraints Verification
- RAM <85%: ✅ 75.7%
- VRAM <4GB: ✅ 10.6% (Ollama CPU), llama.cpp+Vulkan 1.5B ~25%
- All profiles: ✅ git, infra, doc, proxmox — tested
- RAG citations: ✅ All queries return source + line context
- Swap safe: ⚠️ 2.5GB — monitor, consider adding RAM

## Next Recommended
- `sdd-verify` — run verification suite against all specs
- `sdd-archive` — archive completed change
- Consider adding RAM to reduce swap pressure
