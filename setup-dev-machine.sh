#!/usr/bin/env bash
set -eu

source tasks/setup-basics.sh
source tasks/setup-sshd.sh
source tasks/configure-firewall.sh
source tasks/setup-docker.sh
source tasks/setup-lm-studio.sh

# for further configurations use the setup scripts in tasks/