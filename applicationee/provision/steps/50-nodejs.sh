#!/usr/bin/env bash
set -euxo pipefail

# Installs Node.js and npm system-wide from NodeSource's apt repository. Run
# through run.sh.

# Matches @types/node in the project's package.json.
NODE_MAJOR=22

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /etc/apt/keyrings/nodesource.asc
chmod a+r /etc/apt/keyrings/nodesource.asc
cat > /etc/apt/sources.list.d/nodesource.sources <<SOURCES
Types: deb
URIs: https://deb.nodesource.com/node_${NODE_MAJOR}.x
Suites: nodistro
Components: main
Signed-By: /etc/apt/keyrings/nodesource.asc
SOURCES
# Ubuntu has its own nodejs package, possibly of another major version.
# Prefer NodeSource's, also when Ubuntu's version number is higher.
cat > /etc/apt/preferences.d/nodesource <<'PREFERENCES'
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 600
PREFERENCES

apt-get update
apt-get install -y nodejs

node --version
npm --version
[[ "$(node -p 'process.versions.node.split(".")[0]')" == "${NODE_MAJOR}" ]]
