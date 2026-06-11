# Decision Gate: Phase 2 — ROCm/HIP Optimization

## Date
2026-06-11

## Paths Attempted

### Option A: Docker community image with ROCm gfx803
- **Result**: FAILED
- **Evidence**:
  - No pre-built Docker images found on Docker Hub (`robertrosenbusch/rocm6_gfx803_base:6.4` and `robertrosenbusch/rocm6_gfx803_ollama:latest` not found)
  - Building from the `robertrosenbusch/gfx803_rocm` Dockerfile repo requires 30-60+ minutes and ~10GB+ download
  - EPEL provides ROCm 7.1.1 packages but requires `sudo` (not available) and ROCm 7.x dropped official gfx803 support
  - Kernel 6.12 does have `amdgpu` + `amdkfd` loaded and `/dev/kfd` is accessible

### Option B: llama.cpp with Vulkan from pre-built binaries
- **Result**: SUCCESS
- **Evidence**:
  - Downloaded pre-built `llama-b9596-bin-ubuntu-vulkan-x64.tar.gz` (36MB)
  - Vulkan GPU detected: `AMD Radeon RX 580 2048SP (RADV POLARIS10)`
  - No sudo or cmake needed (pre-compiled binaries)

### Option C: Abort Phase 2
- **Result**: NOT NEEDED — Vulkan fallback works excellently

## Benchmark Results

| Metric | Ollama (CPU) | llama.cpp (Vulkan) | Improvement |
|--------|-------------|-------------------|-------------|
| Generation speed | 8.8 tok/s | 85.3 tok/s | **9.7x faster** |
| Prompt processing | 128 tok/s avg | 768 tok/s | **6x faster** |
| RAM usage | Same baseline | Similar | — |
| VRAM used | N/A | GPU offload | — |

> **Note**: Ollama (homebrew installation) is running on CPU only. The homebrew build does not include the Vulkan backend. This explains the order-of-magnitude difference.

## Decision

**✅ MIGRATE to llama.cpp+Vulkan as default backend**

### Reasoning
1. **ROCm path**: Blocked (no sudo for installing ROCm 7.1.1 packages, no pre-built Docker images)
2. **Ollama+Vulkan**: Not available — Ollama (homebrew) is CPU-only
3. **llama.cpp+Vulkan**: Provides GPU acceleration with 85+ tok/s on RX 580

### New Default Stack
- **Inference engine**: llama.cpp (pre-built Vulkan binaries)
- **API port**: :11434 (Ollama-compatible)
- **Model**: Qwen2.5-Coder-1.5B Q4_K_M (GGUF format)
- **Fallback**: Ollama (CPU) if llama.cpp has issues

### Rollback
- If llama.cpp causes issues: `./scripts/switch-backend.sh ollama` restores Ollama

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| homebrew ollama missing Vulkan | Info | Use llama.cpp for GPU, keep Ollama as CPU fallback |
| No sudo for system packages | Low | Pre-built binaries, ~/.local installs |
| ROCm gfx803 permanently unavailable | Medium | Vulkan provides sufficient performance |
| HDD I/O limits model load speed | Low | Models cached in RAM after load |

## Open Questions
- [ ] Revisit ROCm if GPU-intensive workloads need it (not needed for 1.5B inference)
