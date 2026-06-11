# Model Lifecycle Specification

## Purpose
Gestión del ciclo de vida de modelos: descarga, cuantización, registro y swap por perfil de tarea con monitoreo de recursos para evitar OOM.

## Requirements

### R1: Model Download
The system MUST download models from Hugging Face or GGUF URLs to a local models/ directory. Downloads MUST be resumable.

#### Scenario: Download code model
- GIVEN the request "download qwen2.5-coder:1.5b"
- WHEN the download command is executed
- THEN the model is saved to models/qwen2.5-coder-1.5b-Q4_K_M.gguf
- AND registered in the model registry

#### Scenario: Insufficient disk space
- GIVEN less than 2GB free disk space
- WHEN a download is requested
- THEN the system returns error "insufficient disk space"
- AND the download is cancelled

### R2: Model Quantization
The system MAY quantize FP16 GGUF models using llama.cpp's quantize tool. Supported formats: Q4_K_M, Q5_K_M.

#### Scenario: Quantize downloaded model
- GIVEN a downloaded FP16 GGUF in models/
- WHEN `./scripts/quantize.sh model.gguf Q4_K_M` is run
- THEN the quantized model is saved alongside the original
- AND the model registry is updated

#### Scenario: llama.cpp not built
- GIVEN no llama.cpp build available
- WHEN quantization is requested
- THEN the system returns error with build instructions

### R3: Model Swap by Task Profile
The system MUST swap models based on task profile (code, git, infra, rag) without server restart. The current model MUST be unloaded before loading the new one.

#### Scenario: Profile-based swap
- GIVEN the current model is Qwen2.5-Coder-1.5B (code profile)
- WHEN switching to nomic-embed-text (rag profile)
- THEN the code model is unloaded
- AND the rag model is loaded
- AND no OOM error occurs

#### Scenario: Insufficient resources
- GIVEN insufficient free RAM + VRAM for the target model
- WHEN a swap is requested
- THEN the system returns error "insufficient resources"
- AND the current model is preserved

## Non-functional

| Constraint | Target |
|------------|--------|
| VRAM per active model | ≤85% of 4GB |
| Swap latency | <10s between models |
| Download resume | Supported via range requests |
| Model registry | Tracks name, path, quantization, RAM/VRAM, task profile |

## Dependencies
- llama.cpp (quantize tool)
- Hugging Face CLI or direct URL downloader
- models/ directory, model registry config file
- local-inference backend (for model loading/unloading)
