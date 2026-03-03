#!/usr/bin/env bash
#
# Setup Brave Browser
#
# Description:
#   Installs the Brave web browser on Debian/Ubuntu-based systems by adding
#   the official Brave repository and installing the brave-browser package.
#
# Key Actions:
#   1. Downloads and installs the Brave browser GPG keyring for package verification
#   2. Adds the Brave browser APT repository sources configuration
#   3. Updates the APT package index to include Brave packages
#   4. Installs the brave-browser package
#
# Dependencies:
#   - curl: for downloading repository configuration files
#   - apt: package manager (Debian/Ubuntu-based systems)
#   - sudo: requires administrative privileges
#
# Important URLs:
#   - GPG Keyring: https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
#   - Sources List: https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
#
# Exit Behavior:
#   - Script will exit on any error (set -e)
#   - Script will exit on undefined variables (set -u)
#
set -eu

sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg

sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
sudo apt update

sudo apt install -y brave-browser