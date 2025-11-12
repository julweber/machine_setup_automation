#!/usr/bin/env bash
set -eu

source tasks/setup_basics.sh
source tasks/setup_sshd.sh
source tasks/setup_docker.sh
source tasks/setup_lm_studio.sh
source tasks/configure_firewall.sh

# source tasks/setup_kubernetes.sh
# source tasks/setup_openwebui.sh

# source tasks/setup_rocm.sh

# source tasks/setup_brave.sh
# source tasks/setup_vscode.sh