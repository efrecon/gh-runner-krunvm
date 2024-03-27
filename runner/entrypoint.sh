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

# shellcheck source=../lib/common.sh
. "$RUNNER_ROOTDIR/../lib/common.sh"

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

# Location of a file where to store the token
RUNNER_TOKENFILE=${RUNNER_TOKENFILE:-""}

# Location of the podman configuration files. This should match the content of
# the base/root directory of this repository.
RUNNER_CONTAINERS_CONFDIR=${RUNNER_CONTAINERS_CONFDIR:-"/etc/containers"}
RUNNER_CONTAINERS_CONF="${RUNNER_CONTAINERS_CONFDIR%/}/containers.conf"

# Location of the directory where the runner scripts and binaries will log
RUNNER_LOGDIR=${RUNNER_LOGDIR:-"/var/log/runner"}

# shellcheck disable=SC2034 # Used in sourced scripts
KRUNVM_RUNNER_DESCR="Configure and run the installed GitHub runner"


while getopts "eE:g:G:i:k:l:L:n:p:s:S:t:T:u:Uvh-" opt; do
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
    k) # Location of a file where to store the token
      RUNNER_TOKENFILE="$OPTARG";;
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
      usage 0 "RUNNER";;
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
  if ! [ -d "${RUNNER_WORKDIR%/}" ]; then
    mkdir -p "${RUNNER_WORKDIR%/}"
    verbose "Created runner directory ${RUNNER_WORKDIR%/}"
  fi
  RUNNER_BINROOT="${RUNNER_WORKDIR%/}/runner"
  verbose "Copying runner installation to $RUNNER_BINROOT"
  cp -rf "$RUNNER_INSTDIR" "$RUNNER_BINROOT" 2>/dev/null
  check_command "${RUNNER_BINROOT}/config.sh"
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

  # Store runner registration token in a file, if set
  if [ -n "${RUNNER_TOKENFILE:-}" ]; then
    verbose "Storing runner token in $RUNNER_TOKENFILE"
    printf %s\\n "$RUNNER_TOKEN" > "$RUNNER_TOKENFILE"
  fi
}


# Unregister the runner from GitHub. This will use the runner installation copy
runner_unregister() {
  trap - INT TERM EXIT

  # Remember or request (again) a runner registration token
  if [ "${1:-0}" = "1" ]; then
    verbose "Caught termination signal/request, unregistering runner"
  else
    verbose "Caught regular exit signal, unregistering runner"
  fi
  if [ -n "${RUNNER_PAT:-}" ]; then
    if [ -n "${RUNNER_TOKENFILE:-}" ] && [ -f "$RUNNER_TOKENFILE" ]; then
      verbose "Reading runner token from $RUNNER_TOKENFILE"
      RUNNER_TOKEN=$(cat "$RUNNER_TOKENFILE")
    fi

    if [ -z "${RUNNER_TOKEN:-}" ]; then
      verbose "Requesting (back) runner token with PAT"
      RUNNER_TOKEN=$( TOKEN_VERBOSE=$RUNNER_VERBOSE \
                      "$RUNNER_ROOTDIR/token.sh" \
                        -g "$RUNNER_GITHUB" \
                        -l "$RUNNER_LOG" \
                        -p "$RUNNER_PRINCIPAL" \
                        -s "$RUNNER_SCOPE" \
                        -T "$RUNNER_PAT" )
    fi
  fi

  # Remove the runner from GitHub
  verbose "Removing runner at GitHub"
  runner_control config.sh remove --token "$RUNNER_TOKEN"

  # Remove the runner token file, this is so callers can detect removal and act
  # accordingly -- if necessary.
  if [ -n "${RUNNER_TOKENFILE:-}" ] && [ -f "$RUNNER_TOKENFILE" ]; then
    rm -f "$RUNNER_TOKENFILE"
    verbose "Removed runner token file at $RUNNER_TOKENFILE"
  fi

  # Create a break file to signal that the external runner loop that creates
  # microVMs should stop doing so. Do this when the argument to this function is
  # 1 only, i.e. don't break the loop on regular EXIT signals, but break on INT
  # or TERM (i.e. ctrl-c or kill).
  if [ "${1:-0}" = 1 ] && [ -n "${RUNNER_TOKENFILE:-}" ] && [ -n "${RUNNER_SECRET:-}" ]; then
    printf %s\\n "$RUNNER_SECRET" > "${RUNNER_TOKENFILE%.*}.brk"
  fi

  # Remove any lingering sublog process, if any
  if [ -n "${SUBLOG_PID:-}" ]; then
    kill "$SUBLOG_PID" >/dev/null 2>&1 || true
  fi
}


runner_log() {
  SUBLOG_NAME=$1; shift

  # Start the main program in the background, send its output to a log file
  "$@" > "$RUNNER_LOGDIR/${SUBLOG_NAME}.log" 2>&1 &
  PRG_PID=$!

  # Start the sublog redirector in the background, save its PID
  sublog "$RUNNER_LOGDIR/${SUBLOG_NAME}.log" "$SUBLOG_NAME" &
  SUBLOG_PID=$!

  # Wait for the main program to finish, and once it's gone, kill the sublog
  # redirector
  wait "$PRG_PID"
  kill "$SUBLOG_PID"
}


# Run one of the runner scripts from the installation copy. The implementation
# temporary changes directory before calling the script.
runner_control() {
  cwd=$(pwd)
  cd "$RUNNER_BINROOT"
  script=./${1}; shift
  check_command "$script"
  script_name=$(basename "$script")
  debug "Running $script $*"
  RUNNER_ALLOW_RUNASROOT=1 runner_log "${script_name%.sh}" "$script" "$@"
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
    # Forwards podman's log file (picked containers.conf)
    logpath=$(grep "^events_logfile_path" "$RUNNER_CONTAINERS_CONF"|
              cut -d = -f 2|
              sed -E -e 's/^\s//g' -e 's/\s$//g' -e 's/^"//g' -e 's/"$//g')
    [ -n "$logpath" ] && sublog "$logpath" podmand &
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
RUNNER_PREFIX=${RUNNER_PREFIX:-"${RUNNER_DISTRO}-krunvm"}
RUNNER_NAME=${RUNNER_NAME:-"${RUNNER_PREFIX}-$RUNNER_ID"}

RUNNER_WORKDIR=${RUNNER_WORKDIR:-"/_work/${RUNNER_NAME}"}
if [ -n "${distro:-}" ]; then
  RUNNER_LABELS=${RUNNER_LABELS:-"krunvm,${RUNNER_DISTRO}"}
else
  RUNNER_LABELS=${RUNNER_LABELS:-"krunvm"}
fi

# Find the (versioned) directory containing the full installation of the runner
# binary distribution (unpacked by the installer)
RUNNER_INSTDIR=$(find_pattern "${RUNNER_INSTALL}/runner-*" d | sort -r | head -n 1)
if [ -z "$RUNNER_INSTDIR" ]; then
  error "No runner installation directory found under $RUNNER_INSTALL"
else
  debug "Found unpacked binary distribution at $RUNNER_INSTDIR"
fi

# Construct the runner URL, i.e. where the runner will be registered
RUNNER_SCOPE=$(to_lower "$RUNNER_SCOPE")
debug "Constructing $RUNNER_SCOPE runner URL"
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

# Make directory for logging
mkdir -p "$RUNNER_LOGDIR"
chown "$RUNNER_USER" "$RUNNER_LOGDIR"
chmod g+rw "$RUNNER_LOGDIR"

# Install runner binaries into SEPARATE directory, then configure from there
runner_install
runner_configure

if [ "$#" = 0 ]; then
  warn "No command to run, will take defaults"
  set -- "${RUNNER_WORKDIR%/}/runner/bin/Runner.Listener" run --startuptype service
fi

# Capture termination signals. Pass a boolean to runner_unregister: don't break
# the runners microVM creation loop on regular EXIT signals, but break on INT or
# TERM (i.e. ctrl-c or kill).
trap 'runner_unregister 1' INT TERM
trap 'runner_unregister 0' EXIT

# Start the docker daemon. Prefer podman if available (it will be the only one
# available, unless the dockerd is installed in the future)
if is_true "$RUNNER_DOCKER"; then
  docker_daemon
fi

# Start the runner.
verbose "Starting runner as user '$RUNNER_USER' (current user=$(id -un)): $*"
RUNNER_PID=
case "$RUNNER_USER" in
  root)
    if [ "$(id -u)" = "0" ]; then
      "$@" > "$RUNNER_LOGDIR/runner.log" 2>&1 &
      RUNNER_PID=$!
    else
      error "Cannot start runner as root from non-root user"
    fi
    ;;
  *)
    if id "$RUNNER_USER" >/dev/null 2>&1; then
      if [ "$(id -u)" = "0" ]; then
        verbose "Starting runner as $RUNNER_USER"
        chown -R "$RUNNER_USER" "$RUNNER_WORKDIR"
        runas "$@" > "$RUNNER_LOGDIR/runner.log" 2>&1 &
        RUNNER_PID=$!
      elif [ "$(id -un)" = "$RUNNER_USER" ]; then
        "$@" > "$RUNNER_LOGDIR/runner.log" 2>&1 &
        RUNNER_PID=$!
      else
        error "Cannot start runner as $RUNNER_USER from non-$RUNNER_USER user"
      fi
    else
      error "User $RUNNER_USER does not exist"
    fi
    ;;
esac

if [ -n "$RUNNER_PID" ]; then
  # Start the sublog redirector in the background, save its PID
  sublog "$RUNNER_LOGDIR/runner.log" "runner" &
  SUBLOG_PID=$!

  while [ -n "$(running "$RUNNER_PID")" ]; do
    if [ -n "${RUNNER_TOKENFILE:-}" ] && [ -n "${RUNNER_SECRET:-}" ]; then
      if [ -f "${RUNNER_TOKENFILE%.*}.trm" ]; then
        break=$(cat "${RUNNER_TOKENFILE%.*}.trm")
        if [ "$break" = "$RUNNER_SECRET" ]; then
          verbose "Termination file found, stopping runner"
          kill "$RUNNER_PID"
          runner_unregister 1
        else
          warning "Termination found at ${RUNNER_TOKENFILE%.*}.trm, but it does not match the secret"
        fi
      fi
    fi
    sleep 1
  done
fi
