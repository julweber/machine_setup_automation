# How to manage models via huggingface cli

```bash
# search models
QUERY="Qwen3.6 un"
hf models ls --search "${QUERY}" --sort downloads --limit 10

# check available files for model -> shows model repo files available
MODEL="unsloth/Qwen3.6-35B-A3B-GGUF"
hf download $MODEL --dry-run

# Download model weights -> downloads to $HOME/.cache/huggingface/hub per default
MODEL="unsloth/Qwen3.6-35B-A3B-GGUF"
MODEL_FILES="Qwen3.6-35B-A3B-UD-Q4_K_M.gguf README.md"
hf download $MODEL $MODEL_FILES
```

# Directories
If not using `--local-dir`, all files will be downloaded by default to the cache directory defined by the HF_HOME environment variable. 
You can specify a custom cache using `--cache-dir`. See `hf download --help`.