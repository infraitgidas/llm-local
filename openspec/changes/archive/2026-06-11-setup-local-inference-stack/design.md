# Design: Setup Local Inference Stack

## Technical Approach

Stack en tres fases progresivas. Abstracción compartida: API REST `:11434` (Ollama-compatible). Perfiles YAML en `config/` dictan modelo + system prompt por tarea. CLI via scripts bash (F1-F2) → Python wrapper (F3).

## Decisions

| Decisión | Opciones | Tradeoff | Decisión |
|----------|----------|----------|----------|
| Backend F1 | Ollama vs llama.cpp | Ollama: setup simple, gestión integrada. llama.cpp: +30% tok/s, build manual. | **Ollama+Vulkan** — velocidad de setup primero |
| Backend F2 | ROCm vs Vulkan | ROCm +30% tok/s, gfx803 requiere patch. Vulkan out-of-box. | **llama.cpp+ROCm** — build fuente, fallback Vulkan |
| Vector store | sqlite-vss vs chroma | sqlite-vss: sin server extra. chroma: proceso Python dedicado. | **sqlite-vss** — mínimo overhead RAM |
| Embeddings | nomic-embed-v1.5 vs all-MiniLM | nomic 768-dim mejor recall. all-MiniLM 384-dim más rápido CPU. | **nomic-embed-v1.5** — calidad, se corre una vez |
| Swap | keep-warm vs unload/load | keep-warm: respuesta inmediata, 2x VRAM. unload/load: ahorra VRAM, ~10s delay. | **unload/load** — solo 4GB VRAM |
| CLI | bash scripts vs Python | bash: sin dependencias. Python: argparse, error handling. | **bash F1-F2, Python F3** — progresión natural |

## System Architecture

```
User ──→ CLI ──→ config/profile.yaml ──→ :11434 API
                 │                           │
                 ▼                           ▼
          model-registry.yaml        Ollama / llama.cpp
                                         │
                                    GPU (Vulkan/ROCm)
                                    CPU fallback si OOM

RAG (F3):
  docs/.md → chunk(512t,128ov) → nomic-embed → sqlite-vss
  query → embed → top-5 → augment → generate con citas
```

## Resource Map

| Modelo | Quant | VRAM | RAM | Tok/s |
|--------|-------|------|-----|------------|
| Qwen2.5-Coder-1.5B | Q4_K_M | ~1GB | ~2GB | 15-25 |
| Qwen2.5-Coder-3B | Q5_K_M | ~1.8GB | ~2.5GB | 10-15 |
| nomic-embed-v1.5 | Q8 | ~0.3GB | ~0.5GB | — |

**Offloading**: GPU layers máximos con VRAM <85%. Si OOM → mover capas a CPU, loguear.

**Swap**: unload → free VRAM → check resources → load target. Si no alcanza, error preservando modelo actual.

## Perfiles YAML

```yaml
# config/git.yaml
profile: git
model: qwen2.5-coder:1.5b
quantization: Q4_K_M
system_prompt: config/system-prompts/git-commit.md
context_length: 4096  # diffs largos
temperature: 0.3      # formato preciso
```

Mismo modelo físico entre perfiles git/infra/doc (solo cambia prompt+temperature). F3 agrega swap real entre coder 1.5B ↔ 3B ↔ nomic-embed.

## File Changes

| File | Acción | Descripción |
|------|--------|-------------|
| `scripts/stack-setup.sh` | Create | Instala Ollama + Vulkan SDK + dependencias |
| `scripts/switch-backend.sh` | Create | Cambio Ollama ↔ llama.cpp, mismo puerto |
| `scripts/switch-profile.sh` | Create | Swap de modelo por perfil de tarea |
| `scripts/benchmark.sh` | Create | Tok/s, TTFT, RAM/VRAM peak (3 corridas) |
| `scripts/llama.cpp-build.sh` | Create | Build llama.cpp con ROCm gfx803 |
| `scripts/llama.cpp-serve.sh` | Create | Servir modelo vía llama.cpp server |
| `scripts/rag-import.sh` | Create | Indexación .md → sqlite-vss |
| `scripts/rag-query.sh` | Create | Query semántica con pasajes citados |
| `scripts/model-download.sh` | Create | Descarga GGUF con resume + espacio check |
| `scripts/quantize.sh` | Create | Cuantización Q4_K_M/Q5_K_M |
| `config/git.yaml` | Create | Perfil git assist |
| `config/infra.yaml` | Create | Perfil infra agent |
| `config/doc.yaml` | Create | Perfil RAG documentación |
| `config/proxmox.yaml` | Create | Perfil Proxmox + RAG config |
| `config/system-prompts/git-commit.md` | Create | Prompt: conventional commits |
| `config/system-prompts/git-pr.md` | Create | Prompt: PR summary + change list |
| `config/system-prompts/infra-agent.md` | Create | Prompt: comandos con dry-run |
| `config/system-prompts/documentation.md` | Create | Prompt: responde con fuentes citadas |
| `config/model-registry.yaml` | Create | Catálogo: name, path, quant, VRAM, profile |

## Tests

| Capa | Qué probar | Cómo |
|------|-----------|------|
| Smoke | API responde en :11434 | `curl localhost:11434/api/generate` |
| Benchmark | Tok/s, TTFT, RAM/VRAM | `benchmark.sh` — 3 corridas, promedio |
| Resource | Swap no causa OOM | Medir `free -m` + `rocm-smi` antes/después |
| RAG | Query devuelve pasajes con fuente | Importar test docs, verificar top-5 match |
| Failure | Backend caído, disco lleno | Test error paths: 404, insufficient disk, build missing |

## Phase Rollout

| Fase | Dependencia | Criterio | Rollback |
|------|-------------|----------|----------|
| 1: Ollama+Vulkan | — | Prompt <5s, ≥10 tok/s | `apt remove ollama` |
| 2: llama.cpp+ROCm | Build gfx803 exitoso | +30% tok/s vs F1 | Borrar build, restaurar Ollama |
| 3: Multi-model+RAG | nomic-embed + sqlite-vss | Swap sin OOM, RAG cita fuentes | Borrar modelos extra + index |

No migration required.

## Open Questions

- [ ] **ROCm gfx803**: ¿Compila HIP para RX 580 2048SP? Si no, F2 descartado.
- [ ] **Context window**: ¿2048 alcanza para diffs >200 líneas? Spec pide 4096.
- [ ] **HDD penalty**: ¿Ramdisk para modelo activo viable?
- [ ] **Swap timeout**: ¿10s aceptable para cambio de perfil?
