#!/bin/bash

set -euo pipefail

echo "Installing latest node version..."
nvm install node

echo "Installing pi coding agent..."
npm install -g @mariozechner/pi-coding-agent