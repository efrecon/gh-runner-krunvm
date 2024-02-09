#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu


# This is a readlink -f implementation so this script can (perhaps) run on MacOS
abspath() {
  is_abspath() {
    case "$1" in
      /* | ~*) true;;
      *) false;;
    esac
  }

  if [ -d "$1" ]; then
    ( cd -P -- "$1" && pwd -P )
  elif [ -L "$1" ]; then
    if is_abspath "$(readlink "$1")"; then
      abspath "$(readlink "$1")"
    else
      abspath "$(dirname "$1")/$(readlink "$1")"
    fi
  else
    printf %s\\n "$(abspath "$(dirname "$1")")/$(basename "$1")"
  fi
}

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
BASE_VERBOSE=${BASE_VERBOSE:-0}

# Should we install the docker CLI?
BASE_DOCKER=${BASE_DOCKER:-0}

# Where to send logs
BASE_LOG=${BASE_LOG:-2}

BASE_USER=${BASE_USER:-runner}
BASE_UID=${BASE_UID:-1001}
BASE_GROUP=${BASE_GROUP:-runner}
BASE_GID=${BASE_GID:-121}

# Name of the "sudo" group - wheel on Fedora, sudo on Ubuntu
BASE_SUDO=${BASE_SUDO:-"wheel"}

# Resolve the root directory hosting this script to an absolute path, symbolic
# links resolved.
BASE_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(abspath "$0")")")" && pwd -P )

BASE_DOCKER_WRAPPER=${BASE_DOCKER_WRAPPER:-$BASE_ROOTDIR/docker.sh}

# shellcheck source=../lib/common.sh
. "$BASE_ROOTDIR/../lib/common.sh"

# shellcheck disable=SC2034 # Used in sourced scripts
KRUNVM_RUNNER_MAIN="Install a base GitHub runner environment in Fedora"

while getopts "dl:vh-" opt; do
  case "$opt" in
    d) # Install docker
      BASE_DOCKER=1;;
    l) # Where to send logs
      BASE_LOG="$OPTARG";;
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

# Pass logging configuration and level to imported scripts
KRUNVM_RUNNER_LOG=$BASE_LOG
KRUNVM_RUNNER_VERBOSE=$BASE_VERBOSE

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
  procps \
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

  # Replace the real docker binary with our wrapper so we will be able to force
  # running containers on the host network.
  docker=$(find_exec docker)
  if [ -z "${docker:-}" ]; then
    error "No docker binary found in PATH"
  fi
  mv -f "$docker" "${docker}.orig"
  verbose "Moved regular docker client to ${docker}.orig, installing wrapper from $BASE_DOCKER_WRAPPER instead"
  mv -f "$BASE_DOCKER_WRAPPER" "$docker"
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
