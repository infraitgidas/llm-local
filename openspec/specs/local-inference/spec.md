# Local Inference Specification

## Purpose
Ejecución LLM local con aceleración GPU via Vulkan/ROCm en hardware AMD (RX 580, 4GB VRAM, 7.5GB RAM). Stack basado en Ollama + llama.cpp.

## Requirements

### R1: Stack Installation
The system MUST install Ollama ≥0.3.0 with Vulkan backend on first run. The system MAY compile llama.cpp from source for ROCm/gfx803 in Phase 2.

#### Scenario: Fresh install with Vulkan
- GIVEN no Ollama installation exists
- WHEN the user runs `./scripts/stack-setup.sh`
- THEN Ollama is installed with Vulkan support
- AND the Ollama service starts successfully

#### Scenario: ROCm compile failure
- GIVEN ROCm compilation for gfx803 fails
- WHEN the install script detects the failure
- THEN it falls back to Vulkan backend
- AND reports the fallback to the user

### R2: Text Generation API
The system MUST expose a REST API at localhost:11434 for text generation. Simple prompts using Qwen2.5-Coder-1.5B Q4_K_M SHOULD respond within 5 seconds.

#### Scenario: Simple completion
- GIVEN the server is running with Qwen2.5-Coder-1.5B
- WHEN POST /api/generate is sent with prompt "def fibonacci(n):"
- THEN the response contains a valid Python implementation
- AND response time is under 5 seconds

#### Scenario: Model not available
- GIVEN a request for an unloaded model
- WHEN a generate request is sent
- THEN the API returns error 404
- AND lists available models

### R3: Backend Switching
The system SHOULD switch between Ollama and llama.cpp backends without restarting the server process. The API endpoint MUST remain at the same port.

#### Scenario: Switch to llama.cpp
- GIVEN Ollama is running with Qwen2.5-Coder-1.5B
- WHEN the user runs `./scripts/switch-backend.sh llama.cpp`
- THEN llama.cpp becomes the active backend
- AND the API responds on the same port

#### Scenario: Invalid backend name
- GIVEN an unknown backend name
- WHEN the switch command is executed
- THEN an error message is shown
- AND the current backend remains unchanged

## Non-functional

| Constraint | Target |
|------------|--------|
| Latency (1.5B Q4) | <5s per simple prompt |
| Latency (3B Q5) | <15s per simple prompt |
| Memory (active) | ≤85% RAM, ≤4GB VRAM |
| Throughput | ≥10 tok/s (1.5B), ≥5 tok/s (3B) |
| Model cap | ≤3B params, Q4_K_M or Q5_K_M |

## Dependencies
- Ollama ≥0.3.0, Mesa RADV / Vulkan SDK
- llama.cpp + ROCm/HIP source build (Phase 2)
- cmake, make, g++, python3
