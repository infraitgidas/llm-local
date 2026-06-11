# Informe del Proyecto: llm-local

> Stack de inferencia local para tareas de documentación, git, infraestructura y Proxmox.
> Hardware: Intel i5-7400 · 7.5GB RAM · AMD RX 580 4GB · HDD 1TB · Linux

---

## 1. Resumen Ejecutivo

Se implementó un stack completo de modelos de lenguaje locales en hardware modesto (sin GPU NVIDIA, RAM limitada a 7.5GB). El proyecto se desarrolló siguiendo la metodología SDD (Spec-Driven Development) con 3 fases progresivas.

### Stack Final

```
llama.cpp+Vulkan  →  Backend principal (GPU, 85 tok/s)
Ollama (CPU)      →  Fallback (~10 tok/s)
switch-backend.sh →  Cambio entre backends en el mismo puerto :11434
```

### Modelos Disponibles

| Modelo | Tamaño | Backend | Tok/s |
|---|---|---|---|
| qwen2.5-coder:1.5b | 0.99 GB | Ollama CPU | 9.7 |
| qwen2.5-coder:1.5b (GGUF) | 0.99 GB | llama.cpp+Vulkan 🏆 | **85.3** |
| qwen2.5-coder:3b | 1.9 GB | Ollama CPU | 5.2 |
| nomic-embed-text | 0.27 GB | Ollama CPU | — (embeddings) |

### Perfiles por Tarea

| Perfil | Modelo | Temp | Uso |
|---|---|---|---|
| git | 1.5B | 0.2 | Commits convencionales, revisión de diff |
| infra | 3B | 0.2 | Sysadmin, scripts bash, comandos |
| doc | 3B | 0.4 | Documentación técnica, README, changelog |
| proxmox | 3B | 0.2 | VMs, CTs, backups (con RAG) |

---

## 2. Arquitectura

```
┌─────────────────────────────────────────────────────┐
│                  CLI / Herramientas                  │
│  scripts/start.sh  stop.sh  status.sh               │
│  scripts/switch-backend.sh  switch-profile.sh        │
│  scripts/git-assist.sh  rag-query.sh  benchmark.sh   │
└──────────────────────┬──────────────────────────────┘
                       │ HTTP (OpenAI-compatible API)
┌──────────────────────▼──────────────────────────────┐
│              API Server (:11434)                     │
│  llama.cpp+Vulkan (default) / Ollama CPU (fallback)  │
│  Endpoints: /v1/chat/completions, /api/generate      │
└──┬──────────────┬──────────────┬────────────────────┘
   │              │              │
   ▼              ▼              ▼
┌────────┐  ┌──────────┐  ┌──────────┐
│ Qwen   │  │ Qwen     │  │ nomic-   │
│ 1.5B   │  │ 3B       │  │ embed    │
│ (git)  │  │ (infra,  │  │ (RAG)    │
│        │  │  doc,    │  │          │
│        │  │  proxmox)│  │          │
└────────┘  └──────────┘  └──────────┘
```

---

## 3. Métricas de Rendimiento

### Benchmark Comparativo

| Backend | Generación (tok/s) | Prompt (tok/s) | TTFT |
|---|---|---|---|
| **llama.cpp+Vulkan (1.5B)** 🏆 | **85.3** | **768** | <10ms |
| Ollama CPU (1.5B) | 9.7 | 128 | 311ms |
| Ollama CPU (3B) | 5.2 | 85 | 541ms |

El salto de Ollama CPU a llama.cpp+Vulkan representa una mejora de **9.7x** en velocidad de generación.

### RAG

- Latencia promedio de consulta: **170ms**
- 8 chunks indexados de documentación de Proxmox e infraestructura
- 3/3 consultas de prueba exitosas con citas de fuente

### Recursos

| Recurso | En reposo | En carga | Límite |
|---|---|---|---|
| RAM | 3.4 GB libre | 76.4% usado | <85% ✅ |
| VRAM | 868 MB | ~1.2 GB (1.5B Vulkan) | <4GB ✅ |
| Swap | 0 | 2.5 GB | ⚠️ Monitorear |

---

## 4. Lecciones Aprendidas

### Descubrimientos Técnicos

1. **Ollama de Homebrew es CPU-only**: El binario instalado via `brew install ollama` no incluye el backend Vulkan. Para aceleración GPU real hay que usar `llama.cpp` con Vulkan o compilar Ollama desde fuente.

2. **ROCm en gfx803 (RX 580) no es práctico sin sudo**: Aunque la GPU es compatible, la instalación de ROCm 7.x requiere paquetes del sistema (EPEL) que necesitan sudo, no disponible en este entorno.

3. **Vulkan + RX 580 da ~85 tok/s para 1.5B**: Suficiente para tareas interactivas. El modelo 3B no entra en VRAM y corre en CPU (~5 tok/s).

4. **RAG sin dependencias externas**: Usando nomic-embed via Ollama + cosine similarity en bash/JSON es funcional para volúmenes pequeños de documentos.

### Mejoras Recomendadas para el Equipo

| Prioridad | Mejora | Costo | Impacto |
|---|---|---|---|
| 🔴 | 32GB RAM DDR4 | ~$50 | Permite modelos 7B + contexto grande |
| 🔴 | SSD NVMe 1TB | ~$60 | Carga de modelos <1s vs 5-10s |
| 🟡 | RTX 3060 12GB usada | ~$150-200 | CUDA, modelos 7B completos en GPU |
| 🟢 | i7-7700 (4C/8T) | ~$45 | Más hilos para CPU inference |

---

## 5. Estado del Proyecto

- **11 commits** en rama `main`
- **45 archivos**, ~11,168 líneas
- **3 fases completadas**: Stack base → Optimización GPU → Multi-modelo + RAG
- **Verify score**: ~93% post-fixes
- **CI**: GitHub Actions configurado (yamllint + markdownlint + shellcheck)

---

## 6. Commits

```
f376f58 fix: critical issues from sdd-verify (stack-setup, switch-profile timeout, benchmark)
1800f16 docs: mark tasks complete + apply-progress
3f9227d feat: T15 — final benchmark complete
61cf348 feat: T14 — profile switching, quantization, model registry
f350a7d feat: T13 — index Proxmox/infra docs + verify RAG
215addc feat: T12 — RAG pipeline with nomic-embed
529cd21 feat: T11 — config profiles for infra, doc, proxmox
d206994 feat: T10 — model-download.sh + Qwen3B
f932c6f feat: Fase 2 — llama.cpp+Vulkan + benchmark + switch-backend
3bf3551 feat: Fase 1 — Ollama + scripts + git-assist
ee19f42 feat: initial project setup with SDD planning + CI
```
