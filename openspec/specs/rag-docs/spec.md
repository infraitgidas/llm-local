# RAG Docs Specification

## Purpose
RAG local para documentación técnica usando nomic-embed-text para embeddings y sqlite-vss o chroma como vector store. Responde consultas con pasajes relevantes y fuentes citadas.

## Requirements

### R1: Document Indexing
The system MUST index technical documents (Markdown, plain text) into a vector store. It MUST use nomic-embed-text-v1.5 (768-dim) for embeddings with 512-token chunks and 128-token overlap.

#### Scenario: Import documentation directory
- GIVEN a directory of Proxmox documentation (.md files)
- WHEN `./scripts/rag-import.sh /path/to/docs` is run
- THEN all documents are chunked, embedded, and stored in the vector DB
- AND a summary of indexed files is printed

#### Scenario: Incremental re-index
- GIVEN an existing index with some changed files
- WHEN `./scripts/rag-import.sh --update /path/to/docs` is run
- THEN only new and modified files are processed
- AND unchanged files are skipped

### R2: Semantic Query with Citations
The system MUST accept natural language queries and return relevant passages with source file, line range, and relevance score.

#### Scenario: Configuration query
- GIVEN Proxmox docs have been indexed
- WHEN the query is "cómo configurar backup automático"
- THEN the response includes step-by-step instructions
- AND each passage cites its source file and line range

#### Scenario: Out-of-scope query
- GIVEN indexed docs about Proxmox only
- WHEN the query is about an unrelated topic
- THEN the response states "no relevant documentation found"
- AND suggests rephrasing the query

## Non-functional

| Constraint | Target |
|------------|--------|
| Embedding dimension | 768 (nomic-embed-text-v1.5) |
| Chunk size | 512 tokens, 128 overlap |
| Top-k results | 3–5 passages per query |
| Query latency | <2s (embedding + search on CPU) |
| Storage | sqlite-vss or chroma |

## Dependencies
- nomic-embed-text model (via Ollama or sentence-transformers)
- sqlite-vss or chroma, python3 + pip
- local-inference backend (for answer generation from retrieved passages)
