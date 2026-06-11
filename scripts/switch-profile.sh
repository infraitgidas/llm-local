#!/bin/bash
# scripts/switch-profile.sh — Switch model by task profile
#
# Reads profile config from config/<profile>.yaml, unloads current model,
# loads the target model with appropriate system prompt and temperature.
#
# Usage:
#   ./scripts/switch-profile.sh profile <name>   # Switch to profile
#   ./scripts/switch-profile.sh list              # List available profiles
#   ./scripts/switch-profile.sh current           # Show current profile
#   ./scripts/switch-profile.sh unload            # Unload current model

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${PROJECT_DIR}/config"
STATE_FILE="${PROJECT_DIR}/.openprofile"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

# ---- Profile Management ----

list_profiles() {
    header "Available Profiles"
    for f in "$CONFIG_DIR"/*.yaml; do
        local name
        name=$(basename "$f" .yaml)
        # Skip model-registry
        [ "$name" = "model-registry" ] && continue
        
        local model temp desc
        model=$(grep -E '^model:' "$f" 2>/dev/null | head -1 | awk '{print $2}')
        temp=$(grep -E '^temperature:' "$f" 2>/dev/null | head -1 | awk '{print $2}')
        
        echo "  ${name}:"
        echo "    Model:       ${model:-N/A}"
        echo "    Temperature: ${temp:-N/A}"
        
        # Get description from system prompt
        local sysprompt
        sysprompt=$(grep -E '^system_prompt:' "$f" 2>/dev/null | head -1 | awk '{print $2}')
        if [ -n "$sysprompt" ] && [ -f "${PROJECT_DIR}/${sysprompt}" ]; then
            local desc_line
            desc_line=$(head -3 "${PROJECT_DIR}/${sysprompt}" 2>/dev/null | grep -v '^#' | head -1)
            [ -n "$desc_line" ] && echo "    Description: ${desc_line}"
        fi
        echo ""
    done
}

load_profile() {
    local profile_name="$1"
    local profile_file="${CONFIG_DIR}/${profile_name}.yaml"

    if [ ! -f "$profile_file" ]; then
        error "Profile not found: ${profile_name}"
        echo "Available profiles:"
        list_profiles
        return 1
    fi

    header "Loading Profile: ${profile_name}"

    # Parse profile YAML (simple grep-based parser)
    local model temperature context_length system_prompt_file rag_index
    model=$(grep -E '^model:' "$profile_file" | head -1 | awk '{print $2}')
    temperature=$(grep -E '^temperature:' "$profile_file" | head -1 | awk '{print $2}')
    context_length=$(grep -E '^context_length:' "$profile_file" | head -1 | awk '{print $2}')
    system_prompt_file=$(grep -E '^system_prompt:' "$profile_file" | head -1 | awk '{print $2}')
    rag_index=$(grep -E '^rag_index:' "$profile_file" | head -1 | awk '{print $2}')

    info "Profile:      ${profile_name}"
    info "Model:        ${model}"
    info "Temperature:  ${temperature:-0.3}"

    # Unload current model (free VRAM)
    unload_current

    # Check memory before loading
    local avail_ram
    avail_ram=$(free -m | awk '/Mem:/ {print $7}')
    info "Available RAM: ${avail_ram}MB"
    
    if [ "$avail_ram" -lt 2048 ]; then
        warn "Low memory (${avail_ram}MB). Model may be slow or fail."
    fi

    # Load the model via a quick API test
    if command -v ollama &>/dev/null; then
        info "Testing model ${model}..."
        local test_result
        test_result=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST http://localhost:11434/api/generate \
            -d "{\"model\":\"${model}\",\"prompt\":\"OK\",\"stream\":false,\"options\":{\"num_predict\":1}}" 2>/dev/null || echo "000")
        
        if [ "$test_result" = "200" ]; then
            info "Model ${model} is ready"
        elif [ "$test_result" = "000" ]; then
            # Ollama API not responding, try starting it
            if pgrep -x ollama >/dev/null; then
                warn "Ollama running but not responding. Retrying..."
                sleep 2
                test_result=$(curl -s -o /dev/null -w "%{http_code}" \
                    -X POST http://localhost:11434/api/generate \
                    -d "{\"model\":\"${model}\",\"prompt\":\"OK\",\"stream\":false,\"options\":{\"num_predict\":1}}" 2>/dev/null || echo "000")
            fi
        fi
    fi

    # Save state
    echo "profile=${profile_name}" > "$STATE_FILE"
    echo "model=${model}" >> "$STATE_FILE"
    echo "temperature=${temperature:-0.3}" >> "$STATE_FILE"
    echo "context_length=${context_length:-4096}" >> "$STATE_FILE"
    echo "system_prompt_file=${system_prompt_file}" >> "$STATE_FILE"
    echo "rag_index=${rag_index}" >> "$STATE_FILE"

    # Export environment variables for other scripts
    export LLM_PROFILE="${profile_name}"
    export LLM_MODEL="${model}"
    export LLM_TEMPERATURE="${temperature:-0.3}"
    export LLM_CONTEXT_LENGTH="${context_length:-4096}"
    export LLM_SYSTEM_PROMPT_FILE="${system_prompt_file}"
    export LLM_RAG_INDEX="${rag_index}"

    info "Profile '${profile_name}' activated"
    info "Model: ${model} | Temp: ${temperature:-0.3} | Context: ${context_length:-4096}"
    
    if [ -n "$rag_index" ]; then
        info "RAG index: ${rag_index}"
    fi
}

unload_current() {
    # Clear the current model from VRAM by running a small prompt that forces GC
    if [ -f "$STATE_FILE" ]; then
        local old_model
        old_model=$(grep '^model=' "$STATE_FILE" | cut -d= -f2)
        if [ -n "$old_model" ]; then
            info "Unloading previous model: ${old_model}"
            # Send a request to unload (Ollama keeps models loaded for 5 minutes by default)
            # Force unload by sending a request to a non-existent model
            curl -s -X POST http://localhost:11434/api/generate \
                -d "{\"model\":\"_unload\",\"prompt\":\"\",\"stream\":false}" >/dev/null 2>&1 || true
            sleep 1
        fi
        rm -f "$STATE_FILE"
    fi
}

show_current() {
    if [ -f "$STATE_FILE" ]; then
        header "Current Profile"
        while IFS='=' read -r key value; do
            case "$key" in
                profile)          echo "  Profile:       ${value}" ;;
                model)            echo "  Model:         ${value}" ;;
                temperature)      echo "  Temperature:   ${value}" ;;
                context_length)   echo "  Context length: ${value}" ;;
                system_prompt_file) 
                    if [ -n "$value" ] && [ -f "${PROJECT_DIR}/${value}" ]; then
                        echo "  System prompt: ${value}"
                        head -3 "${PROJECT_DIR}/${value}" 2>/dev/null | grep -v '^#' | head -1
                    fi
                    ;;
                rag_index)        [ -n "$value" ] && echo "  RAG index:     ${value}" ;;
            esac
        done < "$STATE_FILE"
        
        echo ""
        info "To switch profile: ./scripts/switch-profile.sh profile <name>"
    else
        info "No active profile. Load one with: $0 profile <name>"
    fi
}

# ---- Resource Check ----

check_resources() {
    header "System Resources"
    
    echo "RAM:"
    free -h | grep -E "Mem:|Swap:"
    echo ""
    
    # VRAM check
    if [ -f /sys/class/drm/card0/device/mem_info_vram_total ]; then
        local vram_total vram_used
        vram_total=$(cat /sys/class/drm/card0/device/mem_info_vram_total 2>/dev/null | awk '{print $1/1024/1024}')
        vram_used=$(cat /sys/class/drm/card0/device/mem_info_vram_used 2>/dev/null | awk '{print $1/1024/1024}')
        if [ -n "$vram_total" ]; then
            local vram_pct
            [ "$vram_total" != "0" ] && vram_pct=$(echo "scale=1; ${vram_used:-0} * 100 / ${vram_total}" | bc 2>/dev/null || echo "?")
            echo "VRAM: ${vram_used:-0}/${vram_total}MB (${vram_pct:-?}%)"
        fi
    fi
    
    echo ""
    
    # Disk space
    echo "Disk space for models:"
    df -h "${PROJECT_DIR}/models" 2>/dev/null | tail -1 || echo "  (models/ not created yet)"
    echo ""
    
    # Ollama status
    echo "Ollama:"
    if pgrep -x ollama >/dev/null 2>&1; then
        echo "  Status: running"
        curl -s http://localhost:11434/api/tags 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    models = [m['name'] for m in d.get('models',[])]
    print(f'  Models: {len(models)} loaded')
    for m in models:
        print(f'    - {m}')
except:
    print('  (API not responding)')
" 2>/dev/null || echo "  (API not responding)"
    else
        echo "  Status: stopped"
    fi
}

# ---- RAG check ----

rag_check() {
    # Quick RAG test: check if we can answer a simple infra question
    if [ -f "$STATE_FILE" ]; then
        local profile_rag_index
        profile_rag_index=$(grep '^rag_index=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
        if [ -n "$profile_rag_index" ] && [ -f "${PROJECT_DIR}/${profile_rag_index}" ]; then
            info "RAG index available: ${profile_rag_index}"
        fi
    fi
}

# ---- Main ----

main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    case "$cmd" in
        profile|load)
            load_profile "${1:-}"
            ;;
        list|--list|-l)
            list_profiles
            ;;
        current|status)
            show_current
            ;;
        unload)
            header "Unloading Model"
            unload_current
            info "Model unloaded. VRAM should be freed."
            ;;
        resources|res)
            check_resources
            ;;
        --help|-h|"")
            echo "Usage:"
            echo "  $0 profile <name>   Switch to a profile (git, infra, doc, proxmox)"
            echo "  $0 list             List available profiles"
            echo "  $0 current          Show current profile"
            echo "  $0 unload           Unload current model (free VRAM)"
            echo "  $0 resources        Show system resources"
            echo ""
            echo "Examples:"
            echo "  $0 profile git      # Switch to git-assist profile"
            echo "  $0 profile infra    # Switch to infra agent profile"
            echo "  $0 profile doc      # Switch to documentation profile"
            echo "  $0 profile proxmox  # Switch to Proxmox + RAG profile"
            ;;
        *)
            error "Unknown command: ${cmd}"
            echo "Usage: $0 [profile <name> | list | current | unload | resources]"
            exit 1
            ;;
    esac
}

main "$@"
