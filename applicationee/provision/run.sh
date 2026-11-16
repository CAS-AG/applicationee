#!/usr/bin/env bash
set -euo pipefail

# Sets up an instance for edimaestro development. createInstance.sh runs this
# on first boot; provision.sh runs it on an instance that is already running.
#
#   sudo ./run.sh <user> [step ...]
#
# <user> is the account everything is set up for (ubuntu on the AMI). Without
# steps, all steps in steps/ run in the order of their number. A step is named
# by its file name without number and .sh, for example "docker" for
# steps/40-docker.sh. Every step can run again on an instance that has it.

STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/steps"

list_steps() {
  for f in "${STEPS_DIR}"/[0-9]*-*.sh; do
    f=$(basename "${f}" .sh)
    echo "  ${f#*-}"
  done
}

if [[ $# -lt 1 ]]; then
  echo "Usage: sudo $0 <user> [step ...]" >&2
  echo "Steps:" >&2
  list_steps >&2
  exit 1
fi
TARGET_USER="$1"
shift

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo $0 ${TARGET_USER} $*" >&2
  exit 1
fi
id "${TARGET_USER}" >/dev/null

STEP_FILES=()
if [[ $# -eq 0 ]]; then
  STEP_FILES=("${STEPS_DIR}"/[0-9]*-*.sh)
else
  for name in "$@"; do
    match=("${STEPS_DIR}"/[0-9]*-"${name}".sh)
    if [[ ! -e "${match[0]}" ]]; then
      echo "Unknown step '${name}'. Steps:" >&2
      list_steps >&2
      exit 1
    fi
    STEP_FILES+=("${match[0]}")
  done
fi

export DEBIAN_FRONTEND=noninteractive
for f in "${STEP_FILES[@]}"; do
  echo "=== Step $(basename "${f}")"
  bash "${f}" "${TARGET_USER}"
done
echo "=== Done: ${#STEP_FILES[@]} step(s)"
