#!/usr/bin/env bash

sudo apt update

sudo apt install ca-certificates curl apt-transport-https

sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY -o /etc/apt/keyrings/keys.anydesk.com.asc

sudo chmod a+r /etc/apt/keyrings/keys.anydesk.com.asc

echo "deb [signed-by=/etc/apt/keyrings/keys.anydesk.com.asc] https://deb.anydesk.com all main" | sudo tee /etc/apt/sources.list.d/anydesk-stable.list

sudo apt update

sudo apt install anydesk
 