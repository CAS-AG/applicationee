#!/usr/bin/env bash
set -euo pipefail

# Copies provision/ to the running instance and runs steps from it, the same
# way createInstance.sh does on first boot. Use it to test changes to a step
# without creating a new instance.
#
# Usage: ./provision.sh [step ...]     e.g. ./provision.sh docker nodejs
# Without steps, all steps run. Run ./provision.sh --list to list them.

# --- Configuration (must match createInstance.sh) --------------------------
# The Elastic IP eipalloc-e15bd5dc; override with HOST=... for another instance.
HOST="${HOST:-35.158.80.129}"
SSH_USER='ubuntu'
KEY_FILE="${KEY_FILE:-$HOME/.ssh/Instana.pem}"
PROVISION_DIR='/opt/edimaestro-provision'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ "${1:-}" == "--list" ]]; then
  for f in "${SCRIPT_DIR}"/provision/steps/[0-9]*-*.sh; do
    f=$(basename "${f}" .sh)
    echo "${f#*-}"
  done
  exit 0
fi

if [[ ! -r "${KEY_FILE}" ]]; then
  echo "Private key ${KEY_FILE} not found. Export it from 1Password or set KEY_FILE." >&2
  exit 1
fi

SSH_OPTS=(-i "${KEY_FILE}" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
remote() { ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" "$@"; }

# Replace the whole directory, so steps deleted locally are gone there too.
STAGING="/tmp/edimaestro-provision.$$"
scp "${SSH_OPTS[@]}" -q -r "${SCRIPT_DIR}/provision" "${SSH_USER}@${HOST}:${STAGING}"
remote "sudo rm -rf ${PROVISION_DIR} && sudo mv ${STAGING} ${PROVISION_DIR} \
  && sudo chown -R root:root ${PROVISION_DIR} && sudo chmod 755 ${PROVISION_DIR}/run.sh"

STEPS=""
[[ $# -gt 0 ]] && STEPS=$(printf ' %q' "$@")
remote "sudo ${PROVISION_DIR}/run.sh ${SSH_USER}${STEPS}"
