#!/usr/bin/env bash
# Set up the Debian 13 host for ProjectCenter's Docker Archive builds.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [--grant-docker-access]

Run from your regular Debian 13 terminal. The script uses sudo for installation
and to start Docker. It also installs bsdtar for local ZIP archives.

--grant-docker-access adds your account to the docker group if needed.
Docker group membership grants root-level access. Sign out and back in
after the group change, then run docker info before starting ProjectCenter.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --grant-docker-access) grant_access=yes; shift ;;
  '') grant_access=no ;;
  *) usage >&2; exit 2 ;;
esac
if (( $# )); then
  usage >&2
  exit 2
fi

die() { printf '%s\n' "$*" >&2; exit 1; }

[[ $EUID != 0 ]] || die "Run this script as the user who runs ProjectCenter."
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 13 ]] ||
  die "This setup script is for Debian 13."

packages=()
if ! command -v docker >/dev/null; then
  packages+=(docker.io docker-cli)
fi
if ! command -v bsdtar >/dev/null; then
  packages+=(libarchive-tools)
fi
if (( ${#packages[@]} )); then
  sudo apt-get update
  sudo apt-get install "${packages[@]}"
fi

if ! docker info >/dev/null 2>&1; then
  if ! systemctl is-active --quiet docker; then
    sudo systemctl start docker
  fi
  if ! docker info >/dev/null 2>&1; then
    socket=/var/run/docker.sock
    if [[ -S "$socket" && ! -w "$socket" && $(stat -c %G "$socket") == docker ]]; then
      if [[ $grant_access == yes ]]; then
        sudo usermod -aG docker "$(id -un)"
        printf '%s\n' "Docker access granted. Sign out and back in, then run docker info."
        exit 0
      fi
      die "Docker is running, but your account cannot access its socket. Rerun with --grant-docker-access if you want to grant root-level Docker access."
    fi
    docker info >&2
  fi
fi

printf '%s\n' "Docker is ready for ProjectCenter Archive under your account."
