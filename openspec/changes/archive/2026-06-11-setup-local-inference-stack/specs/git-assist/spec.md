# Git Assist Specification

## Purpose
Asistencia de git: generación de mensajes de commit convencionales y descripciones de PR analizando el diff con el modelo local.

## Requirements

### R1: Commit Message Generation
The system MUST generate conventional commit messages from a staged or provided diff. Messages MUST follow the conventional commits format (type(scope): description).

#### Scenario: Staged diff → commit message
- GIVEN staged changes in a git repository
- WHEN the user invokes `llm-local git commit`
- THEN output is "feat(auth): add JWT validation" with a body explaining changes
- AND the format follows conventional commits

#### Scenario: Empty diff
- GIVEN no staged changes
- WHEN commit generation is requested
- THEN the system returns error "no changes staged"
- AND exits without calling the model

### R2: PR Description Generation
The system SHOULD generate PR descriptions from a diff between the current branch and main.

#### Scenario: Branch with commits
- GIVEN a branch with 5 commits ahead of main
- WHEN PR description is requested
- THEN output includes a summary, change list, and testing notes

#### Scenario: Branch identical to main
- GIVEN the branch has no changes vs main
- WHEN PR description is requested
- THEN the system returns "no differences found"

### R3: System Prompt Enforcement
The system MUST use a git-specific system prompt that enforces conventional commit format, one-line summary, and structured body.

#### Scenario: Format compliance
- GIVEN any git operation
- WHEN the model generates output
- THEN the output follows the git system prompt format
- AND never outputs raw conversational text

## Non-functional

| Constraint | Target |
|------------|--------|
| Max prompt size | Full diff ≤4096 tokens |
| Output format | One-line summary + body |
| Model | Qwen2.5-Coder-1.5B |

## Dependencies
- git, local-inference backend
- git system prompt template (in config/git-system-prompt.md)
