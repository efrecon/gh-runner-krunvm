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

# Resolve the root directory hosting this script to an absolute path, symbolic
# links resolved.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(abspath "$0")")")" && pwd -P )

# shellcheck source=../lib/common.sh
. "$INSTALL_ROOTDIR/../lib/common.sh"

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
INSTALL_VERBOSE=${INSTALL_VERBOSE:-0}

# Name of the runner project at GitHub
INSTALL_PROJECT=${INSTALL_PROJECT:-"actions/runner"}

# Where to send logs
INSTALL_LOG=${INSTALL_LOG:-2}

# Where to install the runner tar file
INSTALL_DIR=${INSTALL_DIR:-"$INSTALL_ROOTDIR/../share/runner"}

INSTALL_TOOL_CACHE=${INSTALL_TOOL_CACHE:-"${RUNNER_TOOL_CACHE:-"${AGENT_TOOLSDIRECTORY:-"/opt/hostedtoolcache"}"}"}

# Directories to create in environment
INSTALL_DIRECTORIES=${INSTALL_DIRECTORIES:-"/_work $INSTALL_TOOL_CACHE $INSTALL_DIR"}

# User to change ownership of directories to
INSTALL_USER=${INSTALL_USER:-runner}

# shellcheck disable=SC2034 # Used in sourced scripts
KRUNVM_RUNNER_DESCR="Install the GitHub runner"

while getopts "l:u:vh-" opt; do
  case "$opt" in
    l) # Where to send logs
      INSTALL_LOG="$OPTARG";;
    u) # User to install the runner as
      INSTALL_USER="$OPTARG";;
    v) # Increase verbosity, will otherwise log on errors/warnings only
      INSTALL_VERBOSE=$((INSTALL_VERBOSE+1));;
    h) # Print help and exit
      usage 0 "INSTALL";;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))

# Pass logging configuration and level to imported scripts
KRUNVM_RUNNER_LOG=$INSTALL_LOG
KRUNVM_RUNNER_VERBOSE=$INSTALL_VERBOSE

# Collect the version to install from the environment or the first argument.
INSTALL_VERSION=${INSTALL_VERSION:-${1:-latest}}
if [ -z "${INSTALL_VERSION}" ]; then
  error "No version specified"
fi

# When "latest", use the API to request for the latest version of the runner.
if [ "$INSTALL_VERSION" = "latest" ]; then
  debug "Guessing latest version of the runner"
  INSTALL_VERSION=$(curl -sSL "https://api.github.com/repos/${INSTALL_PROJECT}/releases/latest" | jq -r '.tag_name')
fi
INSTALL_VERSION=${INSTALL_VERSION#v}

# Collect the architecture to install from the environment or the second
# argument.
INSTALL_ARCH=${INSTALL_ARCH:-${2:-$(uname -m)}}
case "${INSTALL_ARCH}" in
  x86_64) INSTALL_ARCH=x64;;
  armv7l) INSTALL_ARCH=arm;;
  aarch64) INSTALL_ARCH=arm64;;
  x64) ;;
  arm) ;;
  arm64) ;;
  *) error "Unsupported architecture: ${INSTALL_ARCH}";;
esac

# Download and install the runner
verbose "Downloading version ${INSTALL_VERSION} of the $INSTALL_ARCH runner"
mkdir -p "${INSTALL_DIR}/runner-${INSTALL_VERSION}"
curl -sSL "https://github.com/${INSTALL_PROJECT}/releases/download/v${INSTALL_VERSION}/actions-runner-linux-${INSTALL_ARCH}-${INSTALL_VERSION}.tar.gz" > "${INSTALL_DIR}/${INSTALL_VERSION}.tgz"
verbose "Installing runner to $INSTALL_DIR"
tar -C "${INSTALL_DIR}/runner-${INSTALL_VERSION}" -zxf "${INSTALL_DIR}/${INSTALL_VERSION}.tgz"

# Install the dependencies (this is distro specific and aware)
"${INSTALL_DIR}/runner-${INSTALL_VERSION}/bin/installdependencies.sh"

# Create the directories for the environment. Ensure ownership if a user was
# set.
for dir in $INSTALL_DIRECTORIES; do
  mkdir -p "$dir"
  if [ -n "${INSTALL_USER}" ]; then
    chown -R "${INSTALL_USER}" "$dir"
    verbose "Changed ownership of $dir to ${INSTALL_USER}"
  fi
done
