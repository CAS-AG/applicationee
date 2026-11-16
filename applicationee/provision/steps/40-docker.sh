#!/usr/bin/env bash
set -euxo pipefail

# Installs Docker in rootless mode for the user on Ubuntu: the daemon runs as
# that user, not as root. Run through run.sh.

DOCKER_USER="$1"
DOCKER_UID=$(id -u "${DOCKER_USER}")

# --- Packages from Docker's apt repository ---------------------------------
# uidmap provides newuidmap/newgidmap, dbus-user-session the user bus that
# systemctl --user needs, slirp4netns the network stack for rootless mode.
apt-get update
apt-get install -y ca-certificates curl uidmap dbus-user-session slirp4netns

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
# shellcheck source=/dev/null
CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}")
cat > /etc/apt/sources.list.d/docker.sources <<SOURCES
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
SOURCES
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras \
  docker-buildx-plugin docker-compose-plugin

# The package starts a root daemon; rootless mode does not use it.
systemctl disable --now docker.service docker.socket
rm -f /var/run/docker.sock

# --- AppArmor --------------------------------------------------------------
# Since Ubuntu 24.04, AppArmor blocks unprivileged user namespaces unless a
# profile allows them for the binary. rootlesskit needs them. Newer Ubuntu
# releases ship such a profile; a second profile for the same binary makes
# AppArmor attach neither, so only add one where Ubuntu has none.
UBUNTU_PROFILE='/etc/apparmor.d/rootlesskit'
ROOTLESSKIT_PROFILE='/etc/apparmor.d/usr.bin.rootlesskit'
if [[ -e "${UBUNTU_PROFILE}" ]]; then
  # Left behind by an earlier version of this script.
  if [[ -e "${ROOTLESSKIT_PROFILE}" ]]; then
    apparmor_parser -R "${ROOTLESSKIT_PROFILE}" || true
    rm -f "${ROOTLESSKIT_PROFILE}"
  fi
  apparmor_parser -r "${UBUNTU_PROFILE}"
else
  cat > "${ROOTLESSKIT_PROFILE}" <<'PROFILE'
abi <abi/4.0>,
include <tunables/global>

/usr/bin/rootlesskit flags=(unconfined) {
  userns,

  include if exists <local/usr.bin.rootlesskit>
}
PROFILE
  apparmor_parser -r "${ROOTLESSKIT_PROFILE}"
fi

# --- Subordinate IDs -------------------------------------------------------
# Rootless containers map their UIDs/GIDs into these ranges. useradd usually
# adds them; add them if the user was created without.
grep -q "^${DOCKER_USER}:" /etc/subuid || usermod --add-subuids 100000-165535 "${DOCKER_USER}"
grep -q "^${DOCKER_USER}:" /etc/subgid || usermod --add-subgids 100000-165535 "${DOCKER_USER}"

# --- Rootless daemon -------------------------------------------------------
# Lingering starts the user's systemd instance without a login and keeps the
# daemon running after logout and across reboots.
loginctl enable-linger "${DOCKER_USER}"
for _ in $(seq 30); do
  [[ -S "/run/user/${DOCKER_UID}/bus" ]] && break
  sleep 1
done

# Creates and starts the systemd user service docker.service and switches the
# user's docker CLI to the "rootless" context.
sudo -u "${DOCKER_USER}" -H env \
  XDG_RUNTIME_DIR="/run/user/${DOCKER_UID}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${DOCKER_UID}/bus" \
  bash -eux <<'AS_USER'
dockerd-rootless-setuptool.sh install
systemctl --user enable docker.service
docker info
AS_USER
