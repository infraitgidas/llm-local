# Manual de Uso e Integración: LLM Local Stack

> Cómo usar los modelos locales y conectarlos con asistentes como OpenCode, Windsurf, Cline, y otros.

---

## Índice

1. [Stack Local](#1-stack-local)
2. [Scripts de Gestión](#2-scripts-de-gestión)
3. [Perfiles por Tarea](#3-perfiles-por-tarea)
4. [RAG (Recuperación Aumentada)](#4-rag)
5. [Integración con OpenCode](#5-integración-con-opencode)
6. [Integración con Windsurf / Cline](#6-integración-con-windsurf--cline)
7. [Integración con Cualquier Cliente OpenAI](#7-integración-con-cualquier-cliente-openai)
8. [API Reference](#8-api-reference)
9. [Solución de Problemas](#9-solución-de-problemas)

---

## 1. Stack Local

### Componentes

| Componente | Versión | Puerto |
|---|---|---|
| llama.cpp + Vulkan (default) | b9596 | localhost:11434 |
| Ollama (fallback) | 0.30.7 | localhost:11434 |

### Inicio Rápido

```bash
# 1. Verificar que todo está instalado
./scripts/stack-setup.sh

# 2. Iniciar el servidor (si no está corriendo)
./scripts/start.sh

# 3. Verificar que responde
curl http://localhost:11434/api/tags

# 4. Probar el modelo
ollama run qwen2.5-coder:1.5b "Hola, ¿cómo funciona este stack?"
```

### Backends: Cuándo Usar Cada Uno

| Situación | Backend | Comando |
|---|---|---|
| Uso diario, tareas interactivas | **llama.cpp+Vulkan** 🏆 | `./scripts/start.sh` |
| Modelo 3B (no entra en VRAM) | **Ollama CPU** | `./scripts/switch-backend.sh ollama` |
| Caída de llama.cpp | **Ollama CPU** (fallback) | Automático via `switch-backend.sh` |
| Benchmarking | Ambos | `./scripts/benchmark.sh` |

```bash
# Cambiar de backend
./scripts/switch-backend.sh llama.cpp   # GPU (default, 85 tok/s)
./scripts/switch-backend.sh ollama      # CPU (~10 tok/s)
```

---

## 2. Scripts de Gestión

### Directorio `scripts/`

| Script | Función |
|---|---|
| `start.sh` | Inicia el servidor (detecta backend activo) |
| `stop.sh` | Detiene el servidor gracefulmente |
| `status.sh` | Muestra estado, modelos, y recursos |
| `switch-backend.sh` | Cambia entre llama.cpp ↔ Ollama |
| `switch-profile.sh` | Cambia de perfil (git, infra, doc, proxmox) |
| `git-assist.sh` | Genera commits convencionales desde diff |
| `model-download.sh` | Descarga modelos GGUF con resume |
| `rag-query.sh` | Consulta RAG con búsqueda semántica |
| `rag-import.sh` | Indexa documentos para RAG |
| `quantize.sh` | Cuantiza modelos GGUF |
| `benchmark.sh` | Benchmark de velocidad de inferencia |
| `benchmark-final.sh` | Benchmark completo del stack |
| `llama.cpp-build.sh` | Build/descarga de llama.cpp |
| `llama.cpp-serve.sh` | Gestión del server llama.cpp |
| `stack-setup.sh` | Verificación de instalación completa |

### Ejemplos de Uso

```bash
# Estado del sistema
./scripts/status.sh

# Cambiar a perfil de infraestructura
./scripts/switch-profile.sh profile infra

# Generar commit desde diff stageado
git diff --cached | ./scripts/git-assist.sh

# Consultar documentación de Proxmox
./scripts/rag-query.sh "cómo crear un backup de todas las VMs"

# Benchmark rápido
./scripts/benchmark.sh --quick
```

---

## 3. Perfiles por Tarea

### Perfiles Disponibles

```bash
# Listar perfiles
./scripts/switch-profile.sh list
```

| Perfil | Modelo | Temperatura | System Prompt |
|---|---|---|---|
| **git** | qwen2.5-coder:1.5b | 0.2 | Genera commits convencionales (feat/fix/docs/refactor), revisa diffs |
| **infra** | qwen2.5-coder:3b | 0.2 | Sysadmin Linux, systemd, redes, scripts bash |
| **doc** | qwen2.5-coder:3b | 0.4 | Documentación técnica, README, changelog, API docs |
| **proxmox** | qwen2.5-coder:3b | 0.2 | VMs, CTs, storage, backups + RAG con docs de Proxmox |

### Cambiar de Perfil

```bash
# Activar perfil
./scripts/switch-profile.sh profile git
./scripts/switch-profile.sh profile infra
./scripts/switch-profile.sh profile proxmox

# Ver perfil activo
./scripts/switch-profile.sh current

# Liberar VRAM
./scripts/switch-profile.sh unload
```

### Configuración de Perfiles

Cada perfil es un archivo YAML en `config/`:

```yaml
# config/infra.yaml
model: qwen2.5-coder:3b
temperature: 0.2
context_length: 2048
system_prompt: config/system-prompts/infra-agent.md
```

Y el system prompt correspondiente en `config/system-prompts/`:

```bash
config/
├── git.yaml               # Perfil git
├── infra.yaml             # Perfil infra
├── doc.yaml               # Perfil doc
├── proxmox.yaml           # Perfil proxmox + RAG
├── model-registry.yaml    # Registro de modelos disponibles
└── system-prompts/
    ├── git-commit.md      # System prompt para git
    ├── infra-agent.md     # System prompt para infra/Proxmox
    └── documentation.md   # System prompt para documentación
```

---

## 4. RAG (Recuperación Aumentada)

### Pipeline

```
Documento (.md) → Chunking → Embedding (nomic-embed) → Vector Store (JSON)
                                                              ↓
Query → Embedding → Cosine Similarity → Top-3 Chunks → Contexto → LLM
```

### Indexar Documentos

```bash
# Indexar archivos existentes
./scripts/rag-import.sh docs/proxmox-basics.md

# Indexar todos los .md de un directorio
find docs/ -name "*.md" -exec ./scripts/rag-import.sh {} \;
```

### Consultar

```bash
# Consulta en español
./scripts/rag-query.sh "cómo crear una VM con 2 cores y 4GB RAM"

# Consulta en inglés
./scripts/rag-query.sh "how to configure proxmox backup"

# Consulta específica de infra
./scripts/rag-query.sh "check service status with systemd"
```

### Respuesta Esperada

```
🔍 Consulta: cómo crear una VM con 2 cores y 4GB RAM
📄 Fuente: docs/proxmox-basics.md (coincidencia: 54.9%)
```

---

## 5. Integración con OpenCode

### Opción 1: API Compatible con OpenAI

OpenCode puede usar cualquier API compatible con OpenAI. Configurar en `opencode.json`:

```json
{
  "models": [
    {
      "name": "qwen-local",
      "provider": "openai",
      "baseURL": "http://localhost:11434/v1",
      "apiKey": "no-key-needed",
      "model": "qwen2.5-coder:1.5b"
    }
  ]
}
```

### Opción 2: Agente SDD con Modelo Local

Para usar el modelo local como agente en OpenCode:

```json
{
  "agent": {
    "my-local-agent": {
      "model": {
        "provider": "openai",
        "baseURL": "http://localhost:11434/v1",
        "apiKey": "no-key-needed",
        "model": "qwen2.5-coder:1.5b"
      },
      "mode": "primary"
    }
  }
}
```

### Opción 3: Script Directo

```bash
# Usar git-assist como herramienta en OpenCode
git diff --cached | ./scripts/git-assist.sh
```

### Recomendación para OpenCode

Para tareas de edición de código: usar el modelo remoto de OpenCode (deepseek, gpt-4, etc.) y reservar el modelo local para:
- Commits y revisión de código (`git-assist`)
- Consultas de documentación interna (`rag-query`)
- Operaciones de infraestructura vía comandos

---

## 6. Integración con Windsurf / Cline

### Windsurf (Codeium)

Windsurf permite configurar proveedores personalizados de OpenAI:

1. Abrir Windsurf → Settings → Models
2. Agregar provider personalizado:
   - **URL**: `http://localhost:11434/v1`
   - **API Key**: (vacío o cualquier valor)
   - **Model**: `qwen2.5-coder:1.5b`
3. Asignar nombre: `Qwen Local 1.5B`

### Cline (VS Code Extension)

Cline soporta proveedores OpenAI compatibles:

```json
{
  "cline.models": {
    "qwen-local": {
      "provider": "openai",
      "baseUrl": "http://localhost:11434/v1",
      "apiKey": "",
      "model": "qwen2.5-coder:1.5b"
    }
  }
}
```

### Continue.dev

```json
{
  "models": [
    {
      "title": "Qwen Local 1.5B",
      "provider": "openai",
      "apiBase": "http://localhost:11434/v1",
      "model": "qwen2.5-coder:1.5b"
    }
  ]
}
```

### Consejos de Integración

- **Modelo general (chat, código)**: Usar un modelo potente vía API (DeepSeek, Claude, GPT)
- **Tareas específicas (git, infra, proxmox)**: Usar el modelo local via la API de Ollama/llama.cpp
- **RAG**: Usar `./scripts/rag-query.sh` como tool externa
- **Batch**: Para tareas repetitivas, usar scripts locales que llaman a la API directamente

---

## 7. Integración con Cualquier Cliente OpenAI

### cURL

```bash
# Chat completion (OpenAI-compatible)
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder:1.5b",
    "messages": [
      {"role": "system", "content": "Eres un asistente de infraestructura."},
      {"role": "user", "content": "¿Cómo creo una VM en Proxmox?"}
    ],
    "temperature": 0.2,
    "max_tokens": 512
  }'

# Generación simple
curl http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder:1.5b",
    "prompt": "Explica qué es systemd en una línea.",
    "stream": false
  }'
```

### Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="no-key-needed"
)

response = client.chat.completions.create(
    model="qwen2.5-coder:1.5b",
    messages=[
        {"role": "system", "content": "Eres un asistente de infraestructura."},
        {"role": "user", "content": "Genera un comando para crear una VM con 2 cores y 4GB RAM en Proxmox."}
    ],
    temperature=0.2
)
print(response.choices[0].message.content)
```

### JavaScript / TypeScript

```typescript
const response = await fetch("http://localhost:11434/v1/chat/completions", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    model: "qwen2.5-coder:1.5b",
    messages: [
      { role: "system", content: "Eres un asistente de infraestructura." },
      { role: "user", content: "Genera un comando para crear una VM en Proxmox." }
    ],
    temperature: 0.2
  })
});
const data = await response.json();
console.log(data.choices[0].message.content);
```

---

## 8. API Reference

### Endpoints Disponibles

| Endpoint | Método | Descripción |
|---|---|---|
| `GET /api/tags` | GET | Lista modelos disponibles |
| `POST /api/generate` | POST | Generación simple (Ollama API) |
| `POST /v1/chat/completions` | POST | Chat completion (OpenAI-compatible) |
| `GET /health` | GET | Health check (solo llama.cpp) |

### Parámetros Recomendados

| Parámetro | git | infra | doc | proxmox |
|---|---|---|---|---|
| temperature | 0.2 | 0.2 | 0.4 | 0.2 |
| max_tokens | 256 | 512 | 1024 | 512 |
| context_length | 2048 | 2048 | 4096 | 2048 |

---

## 9. Solución de Problemas

### El servidor no arranca

```bash
# Verificar estado
./scripts/status.sh

# Ver logs de Ollama
cat /tmp/ollama.log

# Ver logs de llama.cpp
cat /tmp/llama.cpp-server.log

# Forzar inicio con backend específico
./scripts/switch-backend.sh ollama   # Probar con CPU primero
./scripts/switch-backend.sh llama.cpp # Probar con GPU después
```

### El modelo no responde o tarda mucho

```bash
# 1. Verificar que el backend correcto está activo
./scripts/status.sh

# 2. Verificar recursos
free -h

# 3. Si es muy lento: cambiar a modelo 1.5B
./scripts/switch-profile.sh profile git

# 4. Probar conectividad
curl -s http://localhost:11434/api/tags
```

### "model not found"

```bash
# Listar modelos disponibles
ollama list

# Si falta, descargar
ollama pull qwen2.5-coder:1.5b
ollama pull qwen2.5-coder:3b
ollama pull nomic-embed-text
```

### RAG no encuentra resultados

```bash
# Verificar que hay documentos indexados
cat rag-index/docs.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'{len(d)} chunks')"

# Re-indexar
./scripts/rag-import.sh docs/proxmox-basics.md
./scripts/rag-import.sh docs/infra-basics.md
```

### Error de memoria

```bash
# Ver swap
free -h

# Si está cerca de 4GB de swap, liberar:
./scripts/switch-profile.sh unload

# Usar modelo 1.5B en vez de 3B
./scripts/switch-profile.sh profile git
```

---

## Glosario

| Término | Significado |
|---|---|
| **llama.cpp** | Framework de inferencia LLM en C++, optimizado para CPU y GPU via Vulkan/ROCk |
| **Vulkan** | API gráfica multiplataforma. En este stack, acelera la inferencia en la RX 580 |
| **Ollama** | Gestor de modelos LLM con API REST. Versión Homebrew = CPU-only |
| **GGUF** | Formato de modelo cuantizado para llama.cpp |
| **Q4_K_M** | Cuantización 4-bit con buen balance calidad/tamaño |
| **RAG** | Retrieval-Augmented Generation — recupera documentos relevantes antes de generar |
| **nomic-embed** | Modelo de embeddings para búsqueda semántica |
| **System Prompt** | Instrucción inicial que define el comportamiento del modelo |
| **TTFT** | Time To First Token — tiempo hasta que el modelo empieza a generar |
