# Tasks: Setup Local Inference Stack

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~800-1000 |
| 400-line budget risk | High |
| Chained PRs recommended | No |
| Suggested split | Single sequence (local project, no PRs) |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Notes |
|------|------|-------|
| 1 | Stack base: Ollama + Vulkan + git profile | Foundation, verificable con smoke test |
| 2 | ROCm/HIP optimization (llama.cpp) | Independiente, puede saltarse si build falla |
| 3 | Multi-model + RAG | Depende de Fase 1; puede correr en paralelo a Fase 2 |

## Phase 1: Stack Base (Ollama + Vulkan)

- [x] T1: Create `scripts/stack-setup.sh` — install Ollama + Vulkan SDK, verify daemon on :11434
- [x] T2: Download Qwen2.5-Coder-1.5B Q4_K_M via Ollama
- [x] T3: Smoke test — `curl :11434/api/generate` responde <5s con código válido
- [x] T4: Create `config/git.yaml` + `config/system-prompts/git-commit.md` + git-pr.md
- [x] T5: Test git-assist — empty diff error, staged diff genera conventional commit

## Phase 2: ROCm/HIP Optimization (llama.cpp)

- [x] T6: Create `scripts/llama.cpp-build.sh` — build llama.cpp con HIP/gfx803, fallback Vulkan
- [x] T7: Create `scripts/llama.cpp-serve.sh` + `scripts/switch-backend.sh` — switch backend mismo puerto
- [x] T8: Create `scripts/benchmark.sh` — tok/s, TTFT, RAM/VRAM peak (3 corridas)
- [x] T9: Decision gate — ROCm no compila, llama.cpp+Vulkan 9.7x faster que Ollama CPU → migrar a llama.cpp default

## Phase 3: Multi-model + RAG

- [x] T10: Create `scripts/model-download.sh` + download Qwen2.5-Coder-3B Q5_K_M con resume
- [x] T11: Create `config/infra.yaml`, `config/doc.yaml`, `config/proxmox.yaml` + system prompts
- [x] T12: Create `scripts/rag-import.sh` + `scripts/rag-query.sh` — nomic-embed + sqlite-vss pipeline
- [x] T13: Index Proxmox/infra docs — verificar query con pasajes citados
- [x] T14: Create `scripts/switch-profile.sh` + `scripts/quantize.sh` + `config/model-registry.yaml` — swap 1.5B↔3B↔nomic sin OOM
- [x] T15: Final benchmark — todos los perfiles, RAM<85%, VRAM<4GB, todos los escenarios de spec

### Dependency Graph

```
T1 ── T2 ── T3 ──┐
 │                │
 ├── T4 ── T5     ├── T8 ── T9
 │                │
 ├── T6 ── T7 ────┘
 │
 ├── T10 ── T12 ── T13
 │    │        │
 │    ├────────┼── T14 ── T15
 │    │        │
 └── T11 ──────┘
```
