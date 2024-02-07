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

# shellcheck disable=SC2120 # Function has good default.
random_string() {
  LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "${1:-12}"
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
RUNNER_USER=${RUNNER_USER:-"root"}

# One of repo, org or enterprise
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
RUNNER_INSTALL=${RUNNER_INSTALL:-"/opt/actions-runner"}

# Should the runner auto-update
RUNNER_UPDATE=${RUNNER_UPDATE:-"0"}


RUNNER_TOOL_CACHE=${RUNNER_TOOL_CACHE:-"${AGENT_TOOLSDIRECTORY:-"/opt/hostedtoolcache"}"}


usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 configure and run the installed GitHub runner" && \
    grep "[[:space:]].) #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-zA-Z-])\)/-\1/'
  exit "${1:-0}"
}

while getopts "eg:G:l:L:n:p:s:t:T:u:Uvh-" opt; do
  case "$opt" in
    e) # Ephemeral runner
      RUNNER_EPHEMERAL=1;;
    g) # GitHub host, e.g. github.com or github.example.com
      RUNNER_GITHUB="$OPTARG";;
    G) # Group to attach the runner to
      RUNNER_GROUP="$OPTARG";;
    l) # Where to send logs
      RUNNER_LOG="$OPTARG";;
    L) # Comma separated list of labels to attach to the runner
      RUNNER_LABELS="$OPTARG";;
    n) # Name of the runner to register (random prefixed name will be used if not set)
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
    >&"$RUNNER_LOG"
}
trace() { if [ "${RUNNER_VERBOSE:-0}" -ge "3" ]; then _log "$1" TRC; fi; }
debug() { if [ "${RUNNER_VERBOSE:-0}" -ge "2" ]; then _log "$1" DBG; fi; }
verbose() { if [ "${RUNNER_VERBOSE:-0}" -ge "1" ]; then _log "$1" NFO; fi; }
warn() { _log "$1" WRN; }
error() { _log "$1" ERR && exit 1; }

# shellcheck disable=SC2120 # Take none or one argument
to_lower() {
  if [ -z "${1:-}" ]; then
    tr '[:upper:]' '[:lower:]'
  else
    printf %s\\n "$1" | to_lower
  fi
}

is_true() {
  case "$(to_lower "${1:-}")" in
    1 | true | yes | y | on | t) return 0;;
    *) return 1;;
  esac
}

configure() {
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

  if [ -z "${RUNNER_TOKEN:-}" ]; then
    error "No runner token provided or acquired"
  fi

  set -- \
    --url "$RUNNER_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --work "$RUNNER_WORKDIR" \
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

  verbose "Configuring runner ${RUNNER_NAME}..."
  debug "Configuration details: $*"
  RUNNER_ALLOW_RUNASROOT=1 "$RUNNER_INSTALL/config.sh" "$@"

  if ! [ -d "$RUNNER_WORKDIR" ]; then
    mkdir -p "$RUNNER_WORKDIR"
    verbose "Created work directory $RUNNER_WORKDIR"
  fi
}


unregister() {
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
  RUNNER_ALLOW_RUNASROOT=1 "$RUNNER_INSTALL/config.sh" remove --token "$RUNNER_TOKEN"
}


# Find the executable passed as an argument in the PATH variable and print it.
find_exec() {
  while IFS= read -r dir; do
    if [ -n "${dir}" ] && [ -d "${dir}" ]; then
      if [ -x "${dir%/}/$1" ] && [ "${dir%/}/$1" != "$(abspath "$0")" ]; then
        printf %s\\n "${dir%/}/$1"
        break
      fi
    fi
  done <<EOF
$(printf %s\\n "$PATH"|tr ':' '\n')
EOF
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

if ! [ -x "$RUNNER_ROOTDIR/token.sh" ]; then
  error "No token script found"
fi
if [ -z "$RUNNER_PRINCIPAL" ]; then
  error "Principal must be set to name of repo, org or enterprise"
fi

debug "Setting up missing defaults"
[ -f "/etc/os-release" ] && . /etc/os-release
RUNNER_DISTRO=${RUNNER_DISTRO:-"${ID:-"unknown}"}"}
RUNNER_NAME_PREFIX=${RUNNER_NAME_PREFIX:-"${RUNNER_DISTRO}-krunvm"}
RUNNER_NAME=${RUNNER_NAME:-"${RUNNER_NAME_PREFIX}-$(random_string)"}

RUNNER_WORKDIR=${RUNNER_WORKDIR:-"/_work/${RUNNER_NAME}"}
if [ -n "${ID:-}" ]; then
  RUNNER_LABELS=${RUNNER_LABELS:-"krunvm,${RUNNER_DISTRO}"}
else
  RUNNER_LABELS=${RUNNER_LABELS:-"krunvm"}
fi

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

# Configure the runner
configure

# Capture termination signals
trap unregister INT TERM QUIT

# Start the docker daemon. Prefer podman if available (it will be the only one
# available, unless the dockerd is installed in the future)
if is_true "$RUNNER_DOCKER"; then
  # Actively look for the binaries in our PATH, so we can make sure the
  # destination user knows where to find them.
  podman=$(find_exec podman)
  dockerd=$(find_exec dockerd)
  # Start one of the daemons, preference podman
  if [ -n "$podman" ]; then
    # Start podman as a service, make sure it can be accessed by the runner
    # user.
    # TODO: Arrange for the user to be able to create the socket file?
    verbose "Starting $podman as a daemon"
    runas "$podman" system service --time=0 unix:///var/run/docker.sock &
  elif [ -n "$dockerd" ]; then
    # For docker, the user must be in the docker group to access the daemon.
    verbose "Starting $dockerd as a daemon"
    $dockerd &
  else
    error "No docker/podman daemon found"
  fi
fi

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
