# Infra Agent Specification

## Purpose
Operaciones de sysadmin y Proxmox asistidas: generación de comandos (pvesh, qm, pct), scripts bash y diagnóstico desde lenguaje natural.

## Requirements

### R1: Proxmox Command Generation
The system MUST generate executable Proxmox commands from natural language descriptions. Output MUST include the full command with all required flags.

#### Scenario: VM creation from description
- GIVEN the prompt "crear VM con 2 cores y 4GB RAM"
- WHEN the infra agent is invoked
- THEN it outputs `qm create <VMID> --cores 2 --memory 4096 --net0 virtio,bridge=vmbr0` with sensible defaults

#### Scenario: Ambiguous resource request
- GIVEN the prompt "crear contenedor" without storage or network details
- WHEN the agent responds
- THEN it uses reasonable defaults for unspecified values
- AND annotates each assumed value

### R2: Service Diagnosis
The system SHOULD analyze service status and suggest remediation steps. Output MUST include check commands and their expected outputs.

#### Scenario: Service down diagnosis
- GIVEN the problem description "pvestatd is stopped"
- WHEN diagnosis is requested
- THEN output includes probable cause, verification commands, and restart procedure

#### Scenario: Unknown service
- GIVEN a non-existent service name
- WHEN diagnosis is requested
- THEN the system reports "service not found"
- AND suggests checking `systemctl list-units`

### R3: Script Generation
The system MAY generate bash scripts for repetitive infrastructure tasks. Generated scripts MUST include safety checks (dry-run mode, usage function).

#### Scenario: Backup script
- GIVEN the request "script to backup all VMs daily"
- WHEN a bash script is requested
- THEN output includes vzdump loop, log rotation, and dry-run flag

## Non-functional

| Constraint | Target |
|------------|--------|
| Command prefix | Always show source (pvesh/qm/pct/bash) |
| Safety | All destructive commands include --dry-run |
| Model | Qwen2.5-Coder-1.5B or 3B |

## Dependencies
- local-inference backend, infra system prompt template
- Proxmox man pages (optional, for context)
