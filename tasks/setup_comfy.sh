#!/usr/bin/env bash
set -eu

# install comfy UI
python3 -m venv comfy-env
source comfy-env/bin/activate
pip install comfy-cli
comfy --install-completion
comfy install
comfy which
comfy --recent which
# Install PyTorch with ROCm support
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.0
comfy launch