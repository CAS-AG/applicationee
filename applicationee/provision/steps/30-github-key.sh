#!/usr/bin/env bash
set -euxo pipefail

# Generates a GitHub deploy key on the instance, so the private key never
# leaves it, and makes ssh use it for github.com. createInstance.sh then
# registers the public key with GitHub and clones the repo. Run through run.sh.

TARGET_USER="$1"

sudo -u "${TARGET_USER}" -H bash -eux <<'AS_USER'
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# Keep an existing key: its public key is already registered with GitHub.
[[ -e ~/.ssh/github_deploy ]] \
  || ssh-keygen -t ed25519 -N '' -f ~/.ssh/github_deploy -C "edimaestro-deploy@$(hostname)"
touch ~/.ssh/config
grep -q '^Host github.com' ~/.ssh/config || cat >> ~/.ssh/config <<'SSH_CONFIG'
Host github.com
  IdentityFile ~/.ssh/github_deploy
  IdentitiesOnly yes
SSH_CONFIG
chmod 600 ~/.ssh/config
ssh-keygen -F github.com >/dev/null || ssh-keyscan github.com >> ~/.ssh/known_hosts
AS_USER
