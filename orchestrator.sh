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
ORCHESTRATOR_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(abspath "$0")")")" && pwd -P )

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
ORCHESTRATOR_VERBOSE=${ORCHESTRATOR_VERBOSE:-0}

# Where to send logs
ORCHESTRATOR_LOG=${ORCHESTRATOR_LOG:-2}

# Name of the OCI image (fully-qualified) to use. You need to have access.
ORCHESTRATOR_IMAGE=${ORCHESTRATOR_IMAGE:-"ghcr.io/efrecon/runner-krunvm:main"}

# Memory to allocate to the VM (in MB). Regular runners use more than the
# default.
ORCHESTRATOR_MEMORY=${ORCHESTRATOR_MEMORY:-"1024"}

# Number of vCPUs to allocate to the VM. Regular runners use more than the
# default.
ORCHESTRATOR_CPUS=${ORCHESTRATOR_CPUS:-"2"}

# Name of the VM to create (krunvm create)
ORCHESTRATOR_NAME=${ORCHESTRATOR_NAME:-"runner"}

# DNS to use on the VM. This is the same as the default in krunvm.
ORCHESTRATOR_DNS=${ORCHESTRATOR_DNS:-"1.1.1.1"}

# Host->VM mount points, lines containing pairs of directory mappings separated
# by a colon.
ORCHESTRATOR_MOUNT=${ORCHESTRATOR_MOUNT:-""}

# Name of top directory in VM where to host a copy of the root directory of this
# script. When this is set, the runner starter script from that directory will
# be used -- instead of the one already in the OCI image. This option is mainly
# usefull for development and testing.
ORCHESTRATOR_DIR=${ORCHESTRATOR_DIR:-""}

# Should the runner be isolated in its own environment. This will pass all
# configuration down to the runner starter script as an environment variable to
# avoid leaking secrets in the command line. The file will be removed as soon as
# used.
ORCHESTRATOR_ISOLATION=${ORCHESTRATOR_ISOLATION:-"1"}

# GitHub host, e.g. github.com or github.example.com
RUNNER_GITHUB=${RUNNER_GITHUB:-"github.com"}

# Group to attach the runner to
RUNNER_GROUP=${RUNNER_GROUP:-"Default"}

# Comma separated list of labels to attach to the runner (good defaults will be used if empty)
RUNNER_LABELS=${RUNNER_LABELS:-""}

# Name of the user to run the runner as, defaults to root. User must exist.
RUNNER_USER=${RUNNER_USER:-"root"}

# Scope of the runner, one of: repo, org or enterprise
RUNNER_SCOPE=${RUNNER_SCOPE:-"repo"}

# Name of organisation, enterprise or repo to attach the runner to, when
# relevant scope.
RUNNER_PRINCIPAL=${RUNNER_PRINCIPAL:-""}

# PAT to acquire runner token with
RUNNER_PAT=${RUNNER_PAT:-""}

# Should the runner auto-update
RUNNER_UPDATE=${RUNNER_UPDATE:-"0"}

# shellcheck source=lib/common.sh
. "$ORCHESTRATOR_ROOTDIR/lib/common.sh"

# shellcheck disable=SC2034 # Used in sourced scripts
KRUNVM_RUNNER_MAIN="Run several krunvm-based GitHub runners on a single host"


while getopts "c:d:D:g:G:i:Il:L:m:M:n:p:s:t:T:u:Uvh-" opt; do
  case "$opt" in
    c) # Number of CPUs to allocate to the VM
      ORCHESTRATOR_CPUS="$OPTARG";;
    d) # DNS server to use in VM
      ORCHESTRATOR_DNS=$OPTARG;;
    D) # Local top VM directory where to host a copy of the root directory of this script (for dev and testing).
      ORCHESTRATOR_DIR=$OPTARG;;
    g) # GitHub host, e.g. github.com or github.example.com
      RUNNER_GITHUB="$OPTARG";;
    G) # Group to attach the runners to
      RUNNER_GROUP="$OPTARG";;
    i) # Fully-qualified name of the OCI image to use
      ORCHESTRATOR_IMAGE="$OPTARG";;
    I) # Turn off variables isolation (not recommended, security risk)
      ORCHESTRATOR_ISOLATION=0;;
    l) # Where to send logs
      ORCHESTRATOR_LOG="$OPTARG";;
    L) # Comma separated list of labels to attach to the runner
      RUNNER_LABELS="$OPTARG";;
    m) # Memory to allocate to the VM
      ORCHESTRATOR_MEMORY="$OPTARG";;
    M) # Mount local host directories into the VM <host dir>:<vm root dir>
      if [ -z "$ORCHESTRATOR_MOUNT" ]; then
        ORCHESTRATOR_MOUNT="$OPTARG"
      else
        ORCHESTRATOR_MOUNT="$(printf %s\\n%s\\n "$ORCHESTRATOR_MOUNT" "$OPTARG")"
      fi;;
    n) # Name of the VM to create
      ORCHESTRATOR_NAME="$OPTARG";;
    p) # Principal to authorise the runner for, name of repo, org or enterprise
      RUNNER_PRINCIPAL="$OPTARG";;
    s) # Scope of the runner, one of repo, org or enterprise
      RUNNER_SCOPE="$OPTARG";;
    T) # Authorization token at the GitHub API to acquire runner token with
      RUNNER_PAT="$OPTARG";;
    u) # User to run the runner as
      RUNNER_USER="$OPTARG";;
    U) # Turn on auto-updating of the runner
      RUNNER_UPDATE=1;;
    v) # Increase verbosity, will otherwise log on errors/warnings only
      ORCHESTRATOR_VERBOSE=$((ORCHESTRATOR_VERBOSE+1));;
    h) # Print help and exit
      usage;;
    -) # End of options. Single argument: number of runners to create
      break;;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))

# Pass logging configuration and level to imported scripts
KRUNVM_RUNNER_LOG=$ORCHESTRATOR_LOG
KRUNVM_RUNNER_VERBOSE=$ORCHESTRATOR_VERBOSE

cleanup() {
  if [ -n "${ORCHESTRATOR_ENVIRONMENT:-}" ]; then
    verbose "Removing isolation environment $ORCHESTRATOR_ENVIRONMENT"
    rm -rf "$ORCHESTRATOR_ENVIRONMENT"
  fi
}

if [ "$#" = 0 ];  then
  error "You need to specify the number of runners to create"
fi
if [ -z "$RUNNER_PAT" ]; then
  error "You need to specify a PAT to acquire the runner token with"
fi

check_command buildah
check_command krunvm

# Remove existing VM with same name.
if run_krunvm list | grep -qE "^$ORCHESTRATOR_NAME"; then
  warn "$ORCHESTRATOR_NAME already exists, recreating"
  run_krunvm delete "$ORCHESTRATOR_NAME"
fi

# Remember number of runners
runners=$1

# Create isolation mount point
if [ "$ORCHESTRATOR_ISOLATION" = 1 ]; then
  ORCHESTRATOR_ENVIRONMENT=$(mktemp -d)
  trap cleanup INT TERM QUIT
fi

# Create the VM used for orchestration. Add --volume options for all necessary
# mappings, i.e. inheritance of "live" code, environment isolation and all
# requested mount points.
verbose "Creating $runners micro VM(s) $ORCHESTRATOR_NAME, $ORCHESTRATOR_CPUS vCPUs, ${ORCHESTRATOR_MEMORY}M memory"
# Note: reset arguments!
set -- \
  --cpus "$ORCHESTRATOR_CPUS" \
  --mem "$ORCHESTRATOR_MEMORY" \
  --dns "$ORCHESTRATOR_DNS" \
  --name "$ORCHESTRATOR_NAME"
set -- "$@" --volume "${ORCHESTRATOR_ROOTDIR}:${ORCHESTRATOR_DIR}"
if [ -n "${ORCHESTRATOR_ENVIRONMENT:-}" ]; then
  set -- "$@" --volume "${ORCHESTRATOR_ENVIRONMENT}:/_environment"
fi
if [ -n "$ORCHESTRATOR_MOUNT" ]; then
  while IFS= read -r mount || [ -n "$mount" ]; do
    if [ -n "$mount" ]; then
      set -- "$@" --volume "$mount"
    fi
  done <<EOF
$(printf %s\\n "$ORCHESTRATOR_MOUNT")
EOF
fi
run_krunvm create "$ORCHESTRATOR_IMAGE" "$@"

# Export all RUNNER_ variables. This works because the 'runner.sh' script that
# will create VM in loops uses variables prefixed with RUNNER_.
while IFS= read -r varname; do
  # shellcheck disable=SC2163 # We want to expand the variable
  export "$varname"
done <<EOF
$(set | grep '^RUNNER_' | sed 's/=.*//')
EOF

# Pass verbosity and log configuration also
RUNNER_VERBOSE=$ORCHESTRATOR_VERBOSE
RUNNER_LOG=$ORCHESTRATOR_LOG
export RUNNER_VERBOSE RUNNER_LOG

# Create runner loops in the background. One per runner. Each loop will
# indefinitely create ephemeral runners. Looping is implemented in runner.sh,
# in the same directory as this script.
set --; # Reset arguments
for i in $(seq 1 "$runners"); do
  if [ -n "${RUNNER_PAT:-}" ]; then
    verbose "Creating runner loop $i"
    "$ORCHESTRATOR_ROOTDIR/runner.sh" \
      -n "$ORCHESTRATOR_NAME" \
      -D "$ORCHESTRATOR_DIR" \
      -E "${ORCHESTRATOR_ENVIRONMENT:-}" &
    set -- "$@" "$!"
  fi
done

verbose "Waiting for runners to die"
for pid in "$@"; do
  wait "$pid"
done
