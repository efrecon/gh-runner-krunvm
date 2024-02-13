#!/usr/bin/dumb-init /bin/sh
# shellcheck shell=sh

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
RUNNER_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(abspath "$0")")")" && pwd -P )

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
RUNNER_VERBOSE=${RUNNER_VERBOSE:-0}

# Where to send logs
RUNNER_LOG=${RUNNER_LOG:-2}

# Name of the runner to register (random prefixed name will be used if empty)
RUNNER_NAME=${RUNNER_NAME:-""}

# GitHub host, e.g. github.com or github.example.com
RUNNER_GITHUB=${RUNNER_GITHUB:-"github.com"}

# Group to attach the runner to
RUNNER_GROUP=${RUNNER_GROUP:-"Default"}

# Comma separated list of labels to attach to the runner (good defaults will be used if empty)
RUNNER_LABELS=${RUNNER_LABELS:-""}

# Name of the user to run the runner as, defaults to root. User must exist.
RUNNER_USER=${RUNNER_USER:-"runner"}

# Scope of the runner, one of: repo, org or enterprise
RUNNER_SCOPE=${RUNNER_SCOPE:-"repo"}

# Name of organisation, enterprise or repo to attach the runner to, when
# relevant scope.
RUNNER_PRINCIPAL=${RUNNER_PRINCIPAL:-""}

# Should the "docker" (will be podman!) daemon be started.
if command -v "docker" >/dev/null 2>&1; then
  RUNNER_DOCKER=${RUNNER_DOCKER:-"1"}
else
  RUNNER_DOCKER=${RUNNER_DOCKER:-"0"}
fi

# Direct runner token, or PAT to acquire runner token with
RUNNER_TOKEN=${RUNNER_TOKEN:-""}
RUNNER_PAT=${RUNNER_PAT:-""}

# Should the runner be ephemeral
RUNNER_EPHEMERAL=${RUNNER_EPHEMERAL:-"0"}

# Root installation of the runner
RUNNER_INSTALL=${RUNNER_INSTALL:-"/opt/gh-runner-krunvm/share/runner"}

# Should the runner auto-update
RUNNER_UPDATE=${RUNNER_UPDATE:-"0"}

# Environment file to read configuration from (will override command-line
# options!). The environment file is automatically removed after reading.
RUNNER_ENVFILE=${RUNNER_ENVFILE:-""}

# Identifier of the runner (used in logs)
RUNNER_ID=${RUNNER_ID:-""}

RUNNER_TOOL_CACHE=${RUNNER_TOOL_CACHE:-"${AGENT_TOOLSDIRECTORY:-"/opt/hostedtoolcache"}"}

# shellcheck source=../lib/common.sh
. "$RUNNER_ROOTDIR/../lib/common.sh"

# shellcheck disable=SC2034 # Used in sourced scripts
KRUNVM_RUNNER_DESCR="Configure and run the installed GitHub runner"


while getopts "eE:g:G:i:l:L:n:p:s:t:T:u:Uvh-" opt; do
  case "$opt" in
    e) # Ephemeral runner
      RUNNER_EPHEMERAL=1;;
    E) # Environment file to read configuration from, will be removed after reading
      RUNNER_ENVFILE="$OPTARG";;
    g) # GitHub host, e.g. github.com or github.example.com
      RUNNER_GITHUB="$OPTARG";;
    G) # Group to attach the runner to
      RUNNER_GROUP="$OPTARG";;
    i) # Identifier of the runner (used in logs and to name the runner)
      RUNNER_ID="$OPTARG";;
    l) # Where to send logs
      RUNNER_LOG="$OPTARG";;
    L) # Comma separated list of labels to attach to the runner
      RUNNER_LABELS="$OPTARG";;
    n) # Name of the runner to register (id or random prefixed name will be used if not set)
      RUNNER_NAME="$OPTARG";;
    p) # Principal to authorise the runner for, name of repo, org or enterprise
      RUNNER_PRINCIPAL="$OPTARG";;
    s) # Scope of the runner, one of repo, org or enterprise
      RUNNER_SCOPE="$OPTARG";;
    t) # Runner token
      RUNNER_TOKEN="$OPTARG";;
    T) # Authorization token at the GitHub API to acquire runner token with
      RUNNER_PAT="$OPTARG";;
    u) # User to run the runner as
      RUNNER_USER="$OPTARG";;
    U) # Turn on auto-updating of the runner
      RUNNER_UPDATE=1;;
    v) # Increase verbosity, will otherwise log on errors/warnings only
      RUNNER_VERBOSE=$((RUNNER_VERBOSE+1));;
    h) # Print help and exit
      usage;;
    -) # End of options, everything after is executed as a command, as relevant user
      break;;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))

# Pass logging configuration and level to imported scripts
KRUNVM_RUNNER_LOG=$RUNNER_LOG
KRUNVM_RUNNER_VERBOSE=$RUNNER_VERBOSE
if [ -z "$RUNNER_ID" ]; then
  RUNNER_ID=$(random_string)
fi
KRUNVM_RUNNER_BIN=$(basename "$0")
KRUNVM_RUNNER_BIN="${KRUNVM_RUNNER_BIN%.sh}-$RUNNER_ID"

# Install a copy of the runner installation into the work directory. Perform a
# minimal verification of the installation through checking that there is a
# config.sh script executable within the copy.
runner_install() {
  # Make a directory where to install a copy of the runner.
  if ! [ -d "${RUNNER_WORKDIR%/}/runner" ]; then
    mkdir -p "${RUNNER_WORKDIR%/}/runner"
    verbose "Created runner directory ${RUNNER_WORKDIR%/}/runner"
  fi
  verbose "Installing runner in ${RUNNER_WORKDIR%/}/runner"
  tar -C "${RUNNER_WORKDIR%/}/runner" -zxf "$RUNNER_TAR"
  check_command "${RUNNER_WORKDIR%/}/runner/config.sh"
}


# Configure the runner and register it at GitHub. This will use the runner
# installation copy from runner_install.
runner_configure() {
  verbose "Registering $RUNNER_SCOPE runner '$RUNNER_NAME' for $RUNNER_URL"
  if [ -n "${RUNNER_PAT:-}" ]; then
    if [ -n "${RUNNER_TOKEN:-}" ]; then
      warn "Both token and PAT are set, using PAT and token will be lost"
    fi
    verbose "Acquiring runner token with PAT"
    RUNNER_TOKEN=$( TOKEN_VERBOSE=$RUNNER_VERBOSE \
                    "$RUNNER_ROOTDIR/token.sh" \
                      -g "$RUNNER_GITHUB" \
                      -l "$RUNNER_LOG" \
                      -p "$RUNNER_PRINCIPAL" \
                      -s "$RUNNER_SCOPE" \
                      -T "$RUNNER_PAT" )
  fi

  # Bail out if no token is available
  if [ -z "${RUNNER_TOKEN:-}" ]; then
    error "No runner token provided or acquired"
  fi

  # Create the work directory. This is where the runner will be working, e.g.
  # checking out repositories, actions, etc.
  if ! [ -d "${RUNNER_WORKDIR%/}/work" ]; then
    mkdir -p "${RUNNER_WORKDIR%/}/work"
    verbose "Created work directory ${RUNNER_WORKDIR%/}/work"
  fi

  # Construct CLI arguments for the runner configuration
  set -- \
    --url "$RUNNER_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --work "${RUNNER_WORKDIR%/}/work" \
    --labels "$RUNNER_LABELS" \
    --runnergroup "$RUNNER_GROUP" \
    --unattended \
    --replace
  if is_true "$RUNNER_EPHEMERAL"; then
    set -- "$@" --ephemeral
  fi
  if ! is_true "$RUNNER_UPDATE"; then
    set -- "$@" --disableupdate
  fi

  # Configure the runner from the installation copy
  verbose "Configuring runner ${RUNNER_NAME}..."
  runner_control config.sh "$@"
}


# Unregister the runner from GitHub. This will use the runner installation copy
runner_unregister() {
  verbose "Caught termination signal, unregistering runner"
  if [ -n "${RUNNER_PAT:-}" ]; then
    verbose "Requesting (back) runner token with PAT"
    RUNNER_TOKEN=$( TOKEN_VERBOSE=$RUNNER_VERBOSE \
                    "$RUNNER_ROOTDIR/token.sh" \
                      -g "$RUNNER_GITHUB" \
                      -l "$RUNNER_LOG" \
                      -p "$RUNNER_PRINCIPAL" \
                      -s "$RUNNER_SCOPE" \
                      -T "$RUNNER_PAT" )
  fi
  verbose "Removing runner at GitHub"
  runner_control config.sh remove --token "$RUNNER_TOKEN"
}


# Run one of the runner scripts from the installation copy. The implementation
# temporary changes directory before calling the script.
runner_control() {
  cwd=$(pwd)
  cd "${RUNNER_WORKDIR%/}/runner"
  script=./${1}; shift
  check_command "$script"
  debug "Running $script $*"
  RUNNER_ALLOW_RUNASROOT=1 "$script" "$@"
  cd "$cwd"
}


docker_daemon() {
  # Actively look for the binaries in our PATH, so we can make sure the
  # destination user knows where to find them.
  podman=$(find_exec podman)
  dockerd=$(find_exec dockerd)
  # Start one of the daemons, preference podman
  if [ -n "$podman" ]; then
    # Start podman as a service, make sure it can be accessed by the runner
    # user.
    verbose "Starting $podman as a daemon"
    "$podman" system service --time=0 unix:///var/run/docker.sock &
    wait_path -S "/var/run/docker.sock" 60
    # Arrange for members of the docker group, which the runner user is a member
    # to be able to access the socket.
    chgrp "docker" /var/run/docker.sock
    chmod g+rw /var/run/docker.sock
  elif [ -n "$dockerd" ]; then
    # For docker, the user must be in the docker group to access the daemon.
    verbose "Starting $dockerd as a daemon"
    $dockerd &
  else
    error "No docker/podman daemon found"
  fi
}


runas() {
  if [ "$(id -u)" = "0" ]; then
    if command -v "runuser" >/dev/null 2>&1; then
      runuser -u "$RUNNER_USER" -- "$@"
    elif command -v "su-exec" >/dev/null 2>&1; then
      su-exec "$RUNNER_USER" "$@"
    else
      cmd=$1; shift
      su -c "$cmd" "$RUNNER_USER" "$@"
    fi
  else
    "$@"
  fi
}

# Read environment file, if set. Do this early on so we can override any other
# variable that would have come from environment or script options.
if [ -n "$RUNNER_ENVFILE" ]; then
  if [ -f "$RUNNER_ENVFILE" ]; then
    verbose "Reading environment file $RUNNER_ENVFILE"
    # shellcheck disable=SC1090 # File has been created by runner.sh loop
    . "$RUNNER_ENVFILE"

    # Pass logging configuration and level to imported scripts (again!) since we
    # might have modified in the .env file.
    KRUNVM_RUNNER_LOG=$RUNNER_LOG
    KRUNVM_RUNNER_VERBOSE=$RUNNER_VERBOSE
    KRUNVM_RUNNER_BIN=$(basename "$0")
    KRUNVM_RUNNER_BIN="${KRUNVM_RUNNER_BIN%.sh}-$RUNNER_ID"

    # Remove the environment file, as it is not needed anymore and might
    # contains secrets.
    rm -f "$RUNNER_ENVFILE"
    debug "Removed environment file $RUNNER_ENVFILE"
  else
    error "Environment file $RUNNER_ENVFILE does not exist"
  fi
fi

# Check requirements.
check_command "$RUNNER_ROOTDIR/token.sh"
if [ -z "$RUNNER_PRINCIPAL" ]; then
  error "Principal must be set to name of repo, org or enterprise"
fi

# Setup variables that would have been missing. These depends on the main
# variables, so we do it here rather than at the top of the script.
debug "Setting up missing defaults"
distro=$(get_env "/etc/os-release" "ID")
RUNNER_DISTRO=${RUNNER_DISTRO:-"${distro:-"unknown}"}"}
RUNNER_NAME_PREFIX=${RUNNER_NAME_PREFIX:-"${RUNNER_DISTRO}-krunvm"}
RUNNER_NAME=${RUNNER_NAME:-"${RUNNER_NAME_PREFIX}-$RUNNER_ID"}

RUNNER_WORKDIR=${RUNNER_WORKDIR:-"/_work/${RUNNER_NAME}"}
if [ -n "${distro:-}" ]; then
  RUNNER_LABELS=${RUNNER_LABELS:-"krunvm,${RUNNER_DISTRO}"}
else
  RUNNER_LABELS=${RUNNER_LABELS:-"krunvm"}
fi

RUNNER_TAR=$(find "$RUNNER_INSTALL" -type f -name "*.tgz" | sort -r | head -n 1)
if [ -z "$RUNNER_TAR" ]; then
  error "No runner tar file found under $RUNNER_INSTALL"
fi

# Construct the runner URL, i.e. where the runner will be registered
debug "Constructing runner URL"
RUNNER_SCOPE=$(to_lower "$RUNNER_SCOPE")
case "$RUNNER_SCOPE" in
  rep*)
    RUNNER_URL="https://${RUNNER_GITHUB%/}/${RUNNER_PRINCIPAL}"
    RUNNER_SCOPE="repo"
    ;;
  org*)
    RUNNER_URL="https://${RUNNER_GITHUB%/}/${RUNNER_PRINCIPAL}"
    RUNNER_SCOPE="org"
    ;;
  ent*)
    RUNNER_URL="https://${RUNNER_GITHUB%/}/enterprises/${RUNNER_PRINCIPAL}"
    RUNNER_SCOPE="enterprise"
    ;;
  *)
    error "Invalid scope: $RUNNER_SCOPE"
    ;;
esac

# Install runner binaries into SEPARATE directory, then configure from there
runner_install
runner_configure

if [ "$#" = 0 ]; then
  warn "No command to run, will take defaults"
  set -- "${RUNNER_WORKDIR%/}/runner/bin/Runner.Listener" run --startuptype service
fi

# Capture termination signals
trap runner_unregister INT TERM QUIT

# Start the docker daemon. Prefer podman if available (it will be the only one
# available, unless the dockerd is installed in the future)
if is_true "$RUNNER_DOCKER"; then
  docker_daemon
fi

verbose "Starting runner as '$RUNNER_USER' (id=$(id -un)): $*"
case "$RUNNER_USER" in
  root)
    if [ "$(id -u)" = "0" ]; then
      "$@"
    else
      error "Cannot start runner as root from non-root user"
    fi
    ;;
  *)
    if id "$RUNNER_USER" >/dev/null 2>&1; then
      if [ "$(id -u)" = "0" ]; then
        verbose "Starting runner as $RUNNER_USER"
        chown -R "$RUNNER_USER" "$RUNNER_INSTALL" "$RUNNER_WORKDIR"
        chown "$RUNNER_USER" "$RUNNER_TOOL_CACHE"
        runas "$@"
      elif [ "$(id -un)" = "$RUNNER_USER" ]; then
        "$@"
      else
        error "Cannot start runner as $RUNNER_USER from non-$RUNNER_USER user"
      fi
    else
      error "User $RUNNER_USER does not exist"
    fi
    ;;
esac
