#!/bin/bash

# Generalized llama-server launcher
# Usage: ./run-llama-server.sh [llama-server args...]

set -e

MODELS_BASE_DIR="$HOME/.lmstudio/models"

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

DEFAULT_PORT=1236
DEFAULT_HOST="127.0.0.1"

# Parse arguments into associative array and collect extra args
declare -A arg_map
llama_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
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
        *)
            llama_args+=("$1")
            shift
            ;;
    esac
done

# Default behavior: if no model specified (and no other args), show available models
if [[ ${#llama_args[@]} -eq 0 ]] && [[ -z "${arg_map[--model]}" ]]; then
    list_models "${arg_map[--model-base-dir]:-}"
fi

# Check if model is specified
if [[ -z "${arg_map[--model]}" ]]; then
    echo "Error: No model specified."
    echo ""
    echo "Usage: ./run-llama-server.sh [llama-server args...]"
    echo "       ./run-llama-server.sh --model /path/to/model.gguf [args...]"
    exit 1
fi

# Set model_to_use from parsed args
model_to_use="${arg_map[--model]}"

# Build final llama-server command
final_args=()

# Add model (required, no default)
final_args+=("--model" "$model_to_use")

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

# Add port from arg_map or default if not specified
if [[ -n "${arg_map[--port]}" ]]; then
    final_args+=("--port" "${arg_map[--port]}")
else
    final_args+=("--port" "$DEFAULT_PORT")
fi

# Add host from arg_map or default if not specified
if [[ -n "${arg_map[--host]}" ]]; then
    final_args+=("--host" "${arg_map[--host]}")
else
    final_args+=("--host" "$DEFAULT_HOST")
fi

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
echo "- Port: ${arg_map[--port]:-$DEFAULT_PORT}"
echo "- Host: ${arg_map[--host]:-$DEFAULT_HOST}"
echo "- Model: $model_to_use"
echo ""
echo "###################################"
echo ""

# Execute llama-server with final arguments
exec llama-server "${final_args[@]}"
