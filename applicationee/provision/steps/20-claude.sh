#!/usr/bin/env bash
set -euxo pipefail

# Installs Claude Code for the user, or updates it. Run through run.sh.

TARGET_USER="$1"

sudo -u "${TARGET_USER}" -H bash -eux <<'AS_USER'
curl -fsSL https://claude.ai/install.sh | bash
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
AS_USER
