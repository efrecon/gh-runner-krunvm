#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
BASE_VERBOSE=${BASE_VERBOSE:-0}

# Should we install the docker CLI?
BASE_DOCKER=${BASE_DOCKER:-0}

BASE_USER=${BASE_USER:-runner}
BASE_UID=${BASE_UID:-1001}
BASE_GROUP=${BASE_GROUP:-runner}
BASE_GID=${BASE_GID:-121}

# Name of the "sudo" group
BASE_SUDO=${BASE_SUDO:-"wheel"}

usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 installs a base GitHub runner environment in Fedora" && \
    grep "[[:space:]].)\ #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-z-])\)/-\1/'
  exit "${1:-0}"
}

while getopts "dvh-" opt; do
  case "$opt" in
    d) # Install docker
      BASE_DOCKER=1;;
    v) # Increase verbosity, will otherwise log on errors/warnings only
      BASE_VERBOSE=$((BASE_VERBOSE+1));;
    h) # Print help and exit
      usage;;
    -) # End of options, everything after are options blindly passed to program before list of files
      break;;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))

# PML: Poor Man's Logging
_log() {
  printf '[%s] [%s] [%s] %s\n' \
    "$(basename "$0")" \
    "${2:-LOG}" \
    "$(date +'%Y%m%d-%H%M%S')" \
    "${1:-}" \
    >&2
}
trace() { if [ "${BASE_VERBOSE:-0}" -ge "3" ]; then _log "$1" TRC; fi; }
debug() { if [ "${BASE_VERBOSE:-0}" -ge "2" ]; then _log "$1" DBG; fi; }
verbose() { if [ "${BASE_VERBOSE:-0}" -ge "1" ]; then _log "$1" NFO; fi; }
warn() { _log "$1" WRN; }
error() { _log "$1" ERR && exit 1; }

# TODO: one of gosu or su-exec to drop privileges and run as the `runner` user
# TODO: locales?
verbose "Installing base packages"
dnf -y install \
  lsb-release \
  curl \
  tar \
  unzip \
  zip \
  sudo \
  ca-certificates \
  @development-tools \
  git-lfs \
  zlib-devel \
  zstd \
  gettext \
  libcurl-devel \
  iputils \
  jq \
  wget \
  dirmngr \
  openssh-clients \
  python3-pip \
  python3-setuptools \
  python3-virtualenv \
  python3 \
  dumb-init \
  nodejs \
  rsync \
  libpq-devel \
  pkg-config \
  podman \
  buildah \
  skopeo \
  'dnf-command(config-manager)'

if [ "$BASE_DOCKER" = "1" ]; then
  verbose "Installing docker"
  dnf -y config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  dnf -y install docker-ce-cli
fi

verbose "Installing gh CLI"
dnf -y config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
dnf -y install gh

verbose "Installing yq"
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod a+x /usr/local/bin/yq

verbose "Creating user (${BASE_USER}:${BASE_UID}) and group (${BASE_GROUP}:${BASE_GID})"
groupadd --gid "$BASE_GID" "$BASE_GROUP"
useradd \
  --system \
  --create-home \
  --home-dir "/home/$BASE_USER" \
  --uid "$BASE_UID" \
  --gid "$BASE_GID" \
  "$BASE_USER"
usermod --append --groups "$BASE_SUDO" "$BASE_USER"
if [ "$BASE_DOCKER" = "1" ]; then
  usermod --append --groups docker "$BASE_USER"
fi
printf '%%%s ALL=(ALL) NOPASSWD: ALL\n' "$BASE_SUDO">> /etc/sudoers
