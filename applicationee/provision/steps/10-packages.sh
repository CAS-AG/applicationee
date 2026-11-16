#!/usr/bin/env bash
set -euxo pipefail

# Base packages the other steps and development need. Run through run.sh.

apt-get update
apt-get install -y ca-certificates curl git
