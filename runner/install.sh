#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
INSTALL_VERBOSE=${INSTALL_VERBOSE:-0}

# Name of the runner project at GitHub
INSTALL_PROJECT=${INSTALL_PROJECT:-"actions/runner"}

# Where to send logs
INSTALL_LOG=${INSTALL_LOG:-2}

# Where to install the runner
INSTALL_DIR=${INSTALL_DIR:-"/opt/actions-runner"}

INSTALL_TOOL_CACHE=${INSTALL_TOOL_CACHE:-"${RUNNER_TOOL_CACHE:-"${AGENT_TOOLSDIRECTORY:-"/opt/hostedtoolcache"}"}"}

# Directories to create in environment
INSTALL_DIRECTORIES=${INSTALL_DIRECTORIES:-"/_work $INSTALL_TOOL_CACHE $INSTALL_DIR"}

# User to change ownership of directories to
INSTALL_USER=${INSTALL_USER:-runner}

usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 install the GitHub runner" && \
    grep "[[:space:]].)\ #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-z-])\)/-\1/'
  exit "${1:-0}"
}

while getopts "l:u:vh-" opt; do
  case "$opt" in
    l) # Where to send logs
      INSTALL_LOG="$OPTARG";;
    u) # User to install the runner as
      INSTALL_USER="$OPTARG";;
    v) # Increase verbosity, will otherwise log on errors/warnings only
      INSTALL_VERBOSE=$((INSTALL_VERBOSE+1));;
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
    >&"$INSTALL_LOG"
}
trace() { if [ "${INSTALL_VERBOSE:-0}" -ge "3" ]; then _log "$1" TRC; fi; }
debug() { if [ "${INSTALL_VERBOSE:-0}" -ge "2" ]; then _log "$1" DBG; fi; }
verbose() { if [ "${INSTALL_VERBOSE:-0}" -ge "1" ]; then _log "$1" NFO; fi; }
warn() { _log "$1" WRN; }
error() { _log "$1" ERR && exit 1; }

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
mkdir -p "$INSTALL_DIR"
curl -sSL "https://github.com/${INSTALL_PROJECT}/releases/download/v${INSTALL_VERSION}/actions-runner-linux-${INSTALL_ARCH}-${INSTALL_VERSION}.tar.gz" > "${INSTALL_DIR}/actions-runner.tgz"
verbose "Installing runner to $INSTALL_DIR"
tar -C "$INSTALL_DIR" -zxf "${INSTALL_DIR}/actions-runner.tgz"
rm -f "${INSTALL_DIR}/actions-runner.tgz"

# Install the dependencies (this is distro specific and aware)
"${INSTALL_DIR}/bin/installdependencies.sh"

# Create the directories for the environment. Ensure ownership if a user was
# set.
for dir in $INSTALL_DIRECTORIES; do
  mkdir -p "$dir"
  if [ -n "${INSTALL_USER}" ]; then
    chown -R "${INSTALL_USER}" "$dir"
    verbose "Changed ownership of $dir to ${INSTALL_USER}"
  fi
done
