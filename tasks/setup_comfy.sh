#!/usr/bin/env bash
#
# Script: setup_comfy.sh
# Description: Automated setup and installation of ComfyUI with ROCm support
#
# This script installs ComfyUI (a powerful and modular stable diffusion GUI) 
# with AMD ROCm GPU acceleration support. It creates an isolated Python virtual 
# environment, installs the ComfyUI CLI tool, and configures PyTorch with ROCm 
# backend for AMD GPU acceleration.
#
# Key Actions:
#   1. Creates a Python virtual environment (comfy-env) for isolated dependencies
#   2. Activates the virtual environment
#   3. Installs comfy-cli package via pip
#   4. Enables shell completion for comfy command
#   5. Runs comfy install to set up ComfyUI components
#   6. Displays ComfyUI installation location
#   7. Shows recent ComfyUI version information
#   8. Installs PyTorch with ROCm 6.0 support for AMD GPU acceleration
#   9. Launches ComfyUI application
#
# Dependencies:
#   - python3 (with venv module)
#   - pip (Python package manager)
#   - AMD ROCm 6.0 drivers (for GPU acceleration)
#   - Internet connection (for downloading packages)
#
# Important Variables:
#   - comfy-env: Name of the Python virtual environment directory
#   - ROCm version: 6.0 (specified in PyTorch installation URL)
#
# Notes:
#   - Script uses 'set -eu' for strict error handling
#   - shellcheck disable=SC1091 suppresses source file warnings
#   - Assumes execution from a directory where comfy-env can be created
#
# shellcheck disable=SC1091
set -eu

# install comfy UI
python3 -m venv comfy-env
source "comfy-env/bin/activate"
pip install comfy-cli
comfy --install-completion
comfy install
comfy which
comfy --recent which
# Install PyTorch with ROCm support
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.0
comfy launch