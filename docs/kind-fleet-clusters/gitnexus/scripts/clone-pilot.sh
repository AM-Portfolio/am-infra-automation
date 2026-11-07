#!/usr/bin/env bash
set -euo pipefail
TOKEN=$(cat /tmp/.gh_tok)
rm -f /tmp/.gh_tok
export GIT_TERMINAL_PROMPT=0
AUTH="https://x-access-token:${TOKEN}@github.com/AM-Portfolio"
id gitnexus >/dev/null
mkdir -p /opt/am/repos
chown -R gitnexus:gitnexus /opt/am
rm -rf /opt/am/gitnexus /opt/am/repos/am-platform
sudo -u gitnexus git clone --depth 1 "${AUTH}/am-gitnexus.git" /opt/am/gitnexus
sudo -u gitnexus git clone --depth 1 "${AUTH}/am-platform.git" /opt/am/repos/am-platform
sudo -u gitnexus git -C /opt/am/gitnexus remote set-url origin https://github.com/AM-Portfolio/am-gitnexus.git
sudo -u gitnexus git -C /opt/am/repos/am-platform remote set-url origin https://github.com/AM-Portfolio/am-platform.git
unset TOKEN AUTH
echo CLONE_OK
ls /opt/am/gitnexus/vps /opt/am/repos/am-platform/.code-intelligence.yaml
