# Proposal: Setup Local Inference Stack

## Intent

Hardware modesto (7.5GB RAM, 4GB VRAM AMD, HDD) impide APIs externas o modelos grandes. Stack local para modelos 1.5B-3B en código, git, infra y documentación — sin costos ni conectividad externa.

## Scope

### In Scope
- Fase 1: Ollama + Vulkan + Qwen2.5-Coder-1.5B — funcional en <30 min
- Fase 2: llama.cpp + ROCm custom para gfx803 — ~30% más rápido
- Fase 3: Multi-modelo (coder 3B + nomic-embed) + RAG local
- Scripts de gestión del stack, benchmarks de rendimiento

### Out of Scope
- Fine-tuning / QLoRA (diferido — requiere Docker + ROCm custom)
- Modelos >3B params (no caben en RAM/VRAM disponibles)
- APIs HTTP externas, interfaz web o UI
- Soporte CUDA/NVIDIA (GPU AMD only)

## Capabilities

### New Capabilities
- `local-inference`: Ejecución LLM local con aceleración GPU via Vulkan/ROCm
- `git-assist`: Operaciones de git asistidas (commits, review, mensajes)
- `infra-agent`: Operaciones de infraestructura y Proxmox asistidas
- `rag-docs`: RAG local con nomic-embed para documentación técnica
- `model-lifecycle`: Descarga, cuantización, y swap de modelos por tarea

### Modified Capabilities
None.

## Approach

Tres fases progresivas, cada una habilita la siguiente:

| Fase | Stack | Modelo | VRAM | RAM | Tok/s (est.) |
|------|-------|--------|------|-----|-------------|
| 1 | Ollama + Vulkan | Qwen2.5-Coder-1.5B Q4 | ~1GB | ~2GB | 15-25 |
| 2 | llama.cpp + ROCm gfx803 | Qwen2.5-Coder-1.5B Q4 | ~1GB | ~1.5GB | 20-32 |
| 3 | Multi-modelo | Coder-3B + nomic-embed | ~2.1GB | ~3GB | 10-15 (3B) |

Fase 1: velocidad de setup. Fase 2: velocidad de inferencia (~30% mejora). Fase 3: capacidad con múltiples modelos y swap por perfil de tarea.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `scripts/` | New | Gestión del stack (start, stop, switch-model) |
| `models/` | New | Almacén de modelos descargados y cuantizados |
| `config/` | New | Perfiles de modelo y system prompts por tarea |
| `docs/rag-index/` | New | Documentación técnica indexada (embeddings) |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| ROCm sin soporte oficial gfx803 | High | Build llama.cpp desde fuente con patch; fallback a Vulkan |
| 3B modelo se sale de VRAM+RAM | Medium | Q5_K_M quantization; si no cabe, limitar a 1.5B |
| HDD lento en carga de modelos | Medium | ramdisk para modelo activo; priorizar SSD como upgrade |
| Ollama + Vulkan crash en RX 580 | Low | Tener llama.cpp Vulkan como alternativa inmediata |

## Rollback Plan

- Fase 1: `ollama rm qwen2.5-coder:1.5b && apt remove ollama`
- Fase 2: eliminar build de llama.cpp, restaurar Ollama como default
- Fase 3: borrar modelos adicionales (`models/*.gguf`) y docs/rag-index/

## Dependencies

- Ollama ≥0.3.0, Vulkan SDK / Mesa RADV drivers (Fase 1)
- ROCm/HIP para gfx803 (Fase 2) — compilación desde fuente
- cmake, make, g++, python3 + pip (embeddings, Fase 3)

## Success Criteria

- [ ] Fase 1: ollama genera respuesta coherente <5s para prompt simple
- [ ] Fase 2: inferencia ~30% más rápida que Ollama Vulkan en el mismo modelo
- [ ] Fase 3: swap entre modelos sin OOM ni errores de segmentación
- [ ] RAG consulta documentación técnica y responde con fuentes citadas
- [ ] RAM en reposo con modelo cargado <85% de uso total
