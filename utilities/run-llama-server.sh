#!/usr/bin/env bash

# Generalized llama-server launcher
# Usage: ./run-llama-server.sh [OPTIONS] [llama-server args...]
#        ./run-llama-server.sh --help

set -e

# Default configuration (can be overridden via arguments)
MODELS_BASE_DIR="$HOME/.lmstudio/models"

# Model path
MODEL_PATH="${MODEL_PATH:-$HOME/.lmstudio/models/HauhauCS/Qwen3.5-35B-A3B-Uncensored-HauhauCS-Aggressive/Qwen3.5-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf}"

# Server binding
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-1236}"

# Generation parameters
TEMPERATURE="${TEMPERATURE:-0.6}"
TOP_K="${TOP_K:-40}"
TOP_P="${TOP_P:-0.95}"
REPEAT_PENALTY="${REPEAT_PENALTY:-1.00}"
PRESENCE_PENALTY="${PRESENCE_PENALTY:-0.00}"
PARALLEL="${PARALLEL:-1}"

# Performance parameters
THREADS_COUNT="${THREADS_COUNT:-14}"
PRIO="${PRIO:-1}"
CONTEXT_SIZE="${CONTEXT_SIZE:-100000}"
BATCH_SIZE="${BATCH_SIZE:-512}"
FLASH_ATTENTION="${FLASH_ATTENTION:-on}"
GPU_LAYERS="${GPU_LAYERS:-all}"
KV_CACHE_TYPE="${KV_CACHE_TYPE:-q4_0}"

# Memory parameters
NO_MMAP="${NO_MMAP:-true}"
KV_UNIFIED="${KV_UNIFIED:-true}"

# Function to list all available model files
list_models() {
    local models_dir="$1"
    if [ -z "$models_dir" ]; then
        models_dir="$MODELS_BASE_DIR"
    fi
    echo "Available GGUF models in $models_dir:"
    echo ""

    if [ ! -d "$models_dir" ]; then
        echo "Models directory not found at: $models_dir"
        exit 1
    fi

    # Find all .gguf files recursively
    model_files=()
    while IFS= read -r -d '' file; do
        model_files+=("$file")
    done < <(find "$models_dir" -type f -name "*.gguf" -print0 2>/dev/null)

    if [ ${#model_files[@]} -eq 0 ]; then
        echo "No .gguf model files found."
        exit 1
    fi

    # Sort and display models with their sizes (full paths, no truncation)
    printf "%s %s\n" "MODEL PATH" "SIZE"
    printf "%s\n" "$(printf '%.0s-' {1..95})"

    for file in "${model_files[@]}"; do
        if [ -f "$file" ]; then
            size=$(du -h "$file" | cut -f1)
            printf "%s %s\n" "$file" "$size"
        fi
    done

    echo ""
    echo "Total models found: ${#model_files[@]}"
    exit 0
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [llama-server args...]

Generalized llama-server launcher. Builds a llama-server command from the
flags below (with sensible defaults) and any extra arguments passed through
as-is. If no --model is given, lists all available GGUF models instead.
Unrecognized arguments are passed through to llama-server.

Options (each takes a value unless noted):
  -m, --model <path>          Path to the GGUF model file
      --model-base-dir <dir>  Directory to search for models (default: ~/.lmstudio/models)
  -p, --port <port>           Server port (default: 1236)
  -b, --host <host>           Bind host (default: 0.0.0.0)
  -t, --temperature <num>     Sampling temperature (default: 0.6)
      --top-k <num>           Top-k sampling (default: 40)
      --top-p <num>           Top-p sampling (default: 0.95)
      --repeat-penalty <num>  Repeat penalty (default: 1.00)
      --presence-penalty <num> Presence penalty (default: 0.00)
      --threads <num>         CPU threads (default: 14)
      --prio <num>            Process priority (default: 1)
      --ctx-size <num>        Context size (default: 100000)
      --batch-size <num>      Batch size (default: 512)
  -fa, --flash-attn <on|off>  Flash attention (default: on)
  -ngl, --n-gpu-layers <n>    GPU layers (default: all/auto)
      --cache-type-k-draft <type> K cache type for draft (default: q4_0)
      --cache-type-v-draft <type> V cache type for draft (default: q4_0)
      --kv-unified            Use unified KV cache (flag)
      --no-mmap               Do not mmap the model (flag)
      --parallel <num>        Parallel slots (default: 1)
  -h, --help                  Show this help and exit

Environment variables (defaults, overridable by flags):
  MODEL_PATH, HOST, PORT, TEMPERATURE, TOP_K, TOP_P, REPEAT_PENALTY,
  PRESENCE_PENALTY, PARALLEL, THREADS_COUNT, PRIO, CONTEXT_SIZE,
  BATCH_SIZE, FLASH_ATTENTION, GPU_LAYERS, KV_CACHE_TYPE, NO_MMAP,
  KV_UNIFIED

Examples:
  $0                              # list available models
  $0 -m /path/to/model.gguf       # start server with defaults
  $0 --model <path> --port 8080   # custom port
  $0 --model <path> -ngl 99       # pass-through/override any llama-server arg
EOF
}

# Parse arguments into associative array and collect extra args
declare -A arg_map
llama_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --model|-m)
            arg_map["--model"]="$2"
            shift 2
            ;;
        --port|-p)
            arg_map["--port"]="$2"
            shift 2
            ;;
        --host|-b)
            arg_map["--host"]="$2"
            shift 2
            ;;
        --model-base-dir|-mbd)
            arg_map["--model-base-dir"]="$2"
            shift 2
            ;;
        --temperature|-t)
            arg_map["--temperature"]="$2"
            shift 2
            ;;
        --top-k)
            arg_map["--top-k"]="$2"
            shift 2
            ;;
        --top-p)
            arg_map["--top-p"]="$2"
            shift 2
            ;;
        --repeat-penalty)
            arg_map["--repeat-penalty"]="$2"
            shift 2
            ;;
        --presence-penalty)
            arg_map["--presence-penalty"]="$2"
            shift 2
            ;;
        --threads)
            arg_map["--threads"]="$2"
            shift 2
            ;;
        --prio)
            arg_map["--prio"]="$2"
            shift 2
            ;;
        --ctx-size)
            arg_map["--ctx-size"]="$2"
            shift 2
            ;;
        --batch-size)
            arg_map["--batch-size"]="$2"
            shift 2
            ;;
        --flash-attn|-fa)
            arg_map["--flash-attn"]="$2"
            shift 2
            ;;
        --n-gpu-layers|-ngl)
            arg_map["--n-gpu-layers"]="$2"
            shift 2
            ;;
        --cache-type-k-draft)
            arg_map["--cache-type-k-draft"]="$2"
            shift 2
            ;;
        --cache-type-v-draft)
            arg_map["--cache-type-v-draft"]="$2"
            shift 2
            ;;
        --kv-unified)
            arg_map["--kv-unified"]="true"
            shift
            ;;
        --no-mmap)
            arg_map["--no-mmap"]="true"
            shift
            ;;
        --parallel)
            arg_map["--parallel"]="$2"
            shift 2
            ;;
        *)
            llama_args+=("$1")
            shift
            ;;
    esac
done

# Default behavior: if no model specified, show available models
if [[ -z "${arg_map[--model]}" ]]; then
    list_models "${arg_map[--model-base-dir]:-}"
fi

# Set model_to_use from parsed args
model_to_use="${arg_map[--model]}"

# Build final llama-server command
final_args=()

# Add model (required, no default)
final_args+=("--model" "$model_to_use")

# Add temperature (default: 0.6)
final_args+=("--temperature" "${arg_map[--temperature]:-$TEMPERATURE}")

# Add top-k (default: 40)
final_args+=("--top-k" "${arg_map[--top-k]:-$TOP_K}")

# Add top-p (default: 0.95)
final_args+=("--top-p" "${arg_map[--top-p]:-$TOP_P}")

# Add repeat-penalty (default: 1.00)
final_args+=("--repeat-penalty" "${arg_map[--repeat-penalty]:-$REPEAT_PENALTY}")

# Add presence-penalty (default: 0.00)
final_args+=("--presence-penalty" "${arg_map[--presence-penalty]:-$PRESENCE_PENALTY}")

# Add threads (default: 14)
final_args+=("--threads" "${arg_map[--threads]:-$THREADS_COUNT}")

# Add prio (default: 1)
final_args+=("--prio" "${arg_map[--prio]:-$PRIO}")

# Add ctx-size (default: 100000)
final_args+=("--ctx-size" "${arg_map[--ctx-size]:-$CONTEXT_SIZE}")

# Add batch-size (default: 512)
final_args+=("--batch-size" "${arg_map[--batch-size]:-$BATCH_SIZE}")

# Add flash-attn (default: on)
final_args+=("--flash-attn" "${arg_map[--flash-attn]:-$FLASH_ATTENTION}")

# Add no-mmap (default: true)
final_args+=("--no-mmap")

# Add n-gpu-layers (default: all)
final_args+=("--n-gpu-layers" "${arg_map[--n-gpu-layers]:-$GPU_LAYERS}")

# Add cache-type-k-draft (default: q4_0)
final_args+=("--cache-type-k-draft" "${arg_map[--cache-type-k-draft]:-$KV_CACHE_TYPE}")

# Add cache-type-v-draft (default: q4_0)
final_args+=("--cache-type-v-draft" "${arg_map[--cache-type-v-draft]:-$KV_CACHE_TYPE}")

# Add kv-unified (default: true)
if [[ "${arg_map[--kv-unified]}" == "true" ]] || [[ "$KV_UNIFIED" == "true" ]]; then
    final_args+=("--kv-unified")
fi

# Add parallel (default: 1)
final_args+=("--parallel" "${arg_map[--parallel]:-$PARALLEL}")

# Flash attention enabled by default (can be overridden with -fa or --flash-attn)
has_fa=false
for arg in "${llama_args[@]}"; do
    if [[ "$arg" == "-fa" ]] || [[ "$arg" == "--flash-attn" ]]; then
        has_fa=true
        break
    fi
done

if [ "$has_fa" = false ]; then
    final_args+=("-fa" "on")
fi

# GPU layers default to auto (can be overridden with -ngl or --n-gpu-layers)
has_gpu_layers_parameter=false
for arg in "${llama_args[@]}"; do
    if [[ "$arg" == "-ngl" ]] || [[ "$arg" == "--n-gpu-layers" ]]; then
        has_gpu_layers_parameter=true
        break
    fi
done

if [ "$has_gpu_layers_parameter" = false ]; then
    final_args+=("-ngl" "auto")
fi

# Add port (default: 1236)
final_args+=("--port" "${arg_map[--port]:-$PORT}")

# Add host (default: 0.0.0.0)
final_args+=("--host" "${arg_map[--host]:-$HOST}")

# Add any remaining llama-server args
for arg in "${llama_args[@]}"; do
    final_args+=("$arg")
done

# Check if model exists before starting server
if [ ! -f "$model_to_use" ]; then
    echo "Error: Model not found at $model_to_use"
    exit 1
fi

# Print startup info
echo "###### Starting llama-server #######"
echo "- Port: ${arg_map[--port]:-$PORT}"
echo "- Host: ${arg_map[--host]:-$HOST}"
echo "- Model: $model_to_use"
echo "- Temperature: ${arg_map[--temperature]:-$TEMPERATURE}"
echo "- Context Size: ${arg_map[--ctx-size]:-$CONTEXT_SIZE}"
echo "- GPU Layers: ${arg_map[--n-gpu-layers]:-$GPU_LAYERS}"
echo ""
echo "###################################"
echo ""

# Execute llama-server with final arguments
exec llama-server "${final_args[@]}"
