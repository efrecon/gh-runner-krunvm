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
RUNNER_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(abspath "$0")")")" && pwd -P )

# shellcheck source=lib/common.sh
. "$RUNNER_ROOTDIR/lib/common.sh"

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
RUNNER_VERBOSE=${RUNNER_VERBOSE:-0}

# Where to send logs
RUNNER_LOG=${RUNNER_LOG:-2}

# Name of the OCI image (fully-qualified) to use. You need to have access.
RUNNER_IMAGE=${RUNNER_IMAGE:-"ghcr.io/efrecon/runner-krunvm-ubuntu:main"}

# Memory to allocate to the VM (in MB). Regular runners use more than the
# default.
RUNNER_MEMORY=${RUNNER_MEMORY:-"1024"}

# Number of vCPUs to allocate to the VM. Regular runners use more than the
# default.
RUNNER_CPUS=${RUNNER_CPUS:-"2"}

# DNS to use on the VM. This is the same as the default in krunvm.
RUNNER_DNS=${RUNNER_DNS:-"1.1.1.1"}

# Host->VM mount points, lines containing pairs of directory mappings separated
# by a colon.
RUNNER_MOUNT=${RUNNER_MOUNT:-""}

# Name of top directory in VM where to host a copy of the root directory of this
# script. When this is set, the runner starter script from that directory will
# be used -- instead of the one already in the OCI image. This option is mainly
# usefull for development and testing.
RUNNER_DIR=${RUNNER_DIR:-""}

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

# PAT to acquire runner token with
RUNNER_PAT=${RUNNER_PAT:-""}

# Should the runner auto-update
RUNNER_UPDATE=${RUNNER_UPDATE:-"0"}

# Prefix to use for the VM names. The VM name will be $RUNNER_PREFIX-xxx
RUNNER_PREFIX=${RUNNER_PREFIX:-"GH-runner"}

# Name of top directory in VM where to host a copy of the root directory of this
# script. When this is set, the runner starter script from that directory will
# be used -- instead of the one already in the OCI image. This option is mainly
# usefull for development and testing.
RUNNER_DIR=${RUNNER_DIR:-""}

RUNNER_MOUNT=${RUNNER_MOUNT:-""}

# Location (at host) where to place environment files for each run.
RUNNER_ENVIRONMENT=${RUNNER_ENVIRONMENT:-""}

# Should the runner be ephemeral, i.e. only run once. There is no CLI option for
# this, since the much preferred behaviour is to run ephemeral runners.
RUNNER_EPHEMERAL=${RUNNER_EPHEMERAL:-"1"}

# Number of times to repeat the runner loop
RUNNER_REPEAT=${RUNNER_REPEAT:-"-1"}

# Secret to be used to request for loop end. Good default is a random string.
RUNNER_SECRET=${RUNNER_SECRET:-"$(random_string)"}

# Number of seconds after which to terminate (empty for never, the good default)
RUNNER_TERMINATE=${RUNNER_TERMINATE:-""}

# shellcheck disable=SC2034 # Used in sourced scripts
KRUNVM_RUNNER_DESCR="Create runners forever using krunvm"


while getopts "c:d:D:g:G:i:l:L:m:M:p:k:r:s:S:T:u:Uvh-" opt; do
  case "$opt" in
    c) # Number of CPUs to allocate to the VM
      RUNNER_CPUS="$OPTARG";;
    d) # DNS server to use in VM
      RUNNER_DNS=$OPTARG;;
    D) # Local top VM directory where to host a copy of the root directory of this script (for dev and testing).
      RUNNER_DIR=$OPTARG;;
    g) # GitHub host, e.g. github.com or github.example.com
      RUNNER_GITHUB="$OPTARG";;
    G) # Group to attach the runner to
      RUNNER_GROUP="$OPTARG";;
    i) # Name of the OCI image (fully-qualified) to use. You need to have access.
      RUNNER_IMAGE="$OPTARG";;
    l) # Where to send logs
      RUNNER_LOG="$OPTARG";;
    L) # Comma separated list of labels to attach to the runner
      RUNNER_LABELS="$OPTARG";;
    m) # Memory to allocate to the VM
      RUNNER_MEMORY="$OPTARG";;
    M) # Mount local host directories into the VM <host dir>:<vm root dir>
      if [ -z "$RUNNER_MOUNT" ]; then
        RUNNER_MOUNT="$OPTARG"
      else
        RUNNER_MOUNT="$(printf %s\\n%s\\n "$RUNNER_MOUNT" "$OPTARG")"
      fi;;
    p) # Principal to authorise the runner for, name of repo, org or enterprise
      RUNNER_PRINCIPAL="$OPTARG";;
    k) # Kill and terminate after this many seconds
      RUNNER_TERMINATE="$OPTARG";;
    r) # Number of times to repeat the runner loop
      RUNNER_REPEAT="$OPTARG";;
    s) # Scope of the runner, one of repo, org or enterprise
      RUNNER_SCOPE="$OPTARG";;
    S) # Secret to be used to request for loop end
      RUNNER_SECRET="$OPTARG";;
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
    -) # End of options, follows the identifier of the runner, if any
      break;;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))

# Pass logging configuration and level to imported scripts
KRUNVM_RUNNER_LOG=$RUNNER_LOG
KRUNVM_RUNNER_VERBOSE=$RUNNER_VERBOSE
loop=${1:-"0"}
if [ -n "${loop:-}" ]; then
  KRUNVM_RUNNER_BIN=$(basename "$0")
  KRUNVM_RUNNER_BIN="${KRUNVM_RUNNER_BIN%.sh}-$loop"
fi

# Name of the root directory in the VM where to map environment and
# synchronisation files.
RUNNER_VM_ENVDIR="_environment"

if [ -z "$RUNNER_PAT" ]; then
  error "You need to specify a PAT to acquire the runner token with"
fi
check_positive_number "$RUNNER_CPUS" "Number of vCPUs"
check_positive_number "$RUNNER_MEMORY" "Memory (in MB)"

# Decide which runner.sh implementation (this is the "entrypoint" of the
# microVM) to use: the one from the mount point, or the built-in one.
if [ -z "$RUNNER_DIR" ]; then
  RUNNER_ENTRYPOINT=/opt/gh-runner-krunvm/bin/entrypoint.sh
else
  check_command "${RUNNER_ROOTDIR}/runner/entrypoint.sh"
  RUNNER_ENTRYPOINT=${RUNNER_DIR%/}/runner/entrypoint.sh
fi

# Create the VM used for orchestration. Add --volume options for all necessary
# mappings, i.e. inheritance of "live" code, environment isolation and all
# requested mount points.
vm_create() {
  verbose "Creating microVM '${RUNNER_PREFIX}-$1', $RUNNER_CPUS vCPUs, ${RUNNER_MEMORY}M memory"
  # Note: reset arguments!
  set -- \
    --cpus "$RUNNER_CPUS" \
    --mem "$RUNNER_MEMORY" \
    --dns "$RUNNER_DNS" \
    --name "${RUNNER_PREFIX}-$1"
  if [ -n "${RUNNER_DIR:-}" ]; then
    set -- "$@" --volume "${RUNNER_ROOTDIR}:${RUNNER_DIR}"
  fi
  if [ -n "${RUNNER_ENVIRONMENT:-}" ]; then
    set -- "$@" --volume "${RUNNER_ENVIRONMENT}:/${RUNNER_VM_ENVDIR}"
  fi
  if [ -n "$RUNNER_MOUNT" ]; then
    while IFS= read -r mount || [ -n "$mount" ]; do
      if [ -n "$mount" ]; then
        set -- "$@" --volume "$mount"
      fi
    done <<EOF
$(printf %s\\n "$RUNNER_MOUNT")
EOF
  fi
  run_krunvm create "$RUNNER_IMAGE" "$@"
}


vm_start() {
  _id=$1
  if [ -n "$RUNNER_ENVIRONMENT" ]; then
    # Create an env file with most of the RUNNER_ variables. This works because
    # the `runner.sh` script that will be called uses the same set of variables.
    verbose "Creating isolation environment ${RUNNER_ENVIRONMENT}/${_id}.env"
    while IFS= read -r varset; do
      # shellcheck disable=SC2163 # We want to expand the variable
      printf '%s\n' "$varset" >> "${RUNNER_ENVIRONMENT}/${_id}.env"
    done <<EOF
$(set | grep '^RUNNER_' | grep -vE '(ROOTDIR|ENVIRONMENT|IMAGE|MEMORY|CPUS|DNS|MOUNT|DIR|PREFIX)')
EOF

    # Pass the location of the env. file to the runner script
    set -- -E "/${RUNNER_VM_ENVDIR}/${_id}.env"

    # Also pass the location of a file that will contain the token.
    set -- -k "/${RUNNER_VM_ENVDIR}/${_id}.tkn" "$@"
  else
    set -- \
        -e \
        -g "$RUNNER_GITHUB" \
        -G "$RUNNER_GROUP" \
        -i "$_id" \
        -l "$RUNNER_LOG" \
        -L "$RUNNER_LABELS" \
        -p "$RUNNER_PRINCIPAL" \
        -s "$RUNNER_SCOPE" \
        -S "$RUNNER_SECRET" \
        -T "$RUNNER_PAT" \
        -u "$RUNNER_USER"
    for _ in $(seq 1 "$RUNNER_VERBOSE"); do
      set -- -v "$@"
    done
  fi
  verbose "Starting microVM '${RUNNER_PREFIX}-$_id' with entrypoint $RUNNER_ENTRYPOINT"
  optstate=$(set +o)
  set -m; # Disable job control
  run_krunvm start "${RUNNER_PREFIX}-$_id" "$RUNNER_ENTRYPOINT" -- "$@" </dev/null &
  RUNNER_PID=$!
  eval "$optstate"; # Restore options
  verbose "Started microVM '${RUNNER_PREFIX}-$_id' with PID $RUNNER_PID"
  if [ -n "$RUNNER_TERMINATE" ]; then
    verbose "Terminating runner in $RUNNER_TERMINATE seconds"
    sleep "$RUNNER_TERMINATE" && cleanup &
  fi
  wait "$RUNNER_PID"
  RUNNER_PID=
}


vm_delete() {
  # This is just a safety measure, the runner script should already have deleted
  # the environment
  if [ -n "$RUNNER_ENVIRONMENT" ] && [ -f "${RUNNER_ENVIRONMENT}/${1}.env" ]; then
    warning "Removing isolation environment ${RUNNER_ENVIRONMENT}/${1}.env"
    rm -f "${RUNNER_ENVIRONMENT}/${1}.env"
  fi
  if run_krunvm list | grep -qE "^${RUNNER_PREFIX}-$1"; then
    verbose "Removing microVM '${RUNNER_PREFIX}-$1'"
    run_krunvm delete "${RUNNER_PREFIX}-$1"
  fi
}

vm_terminate() {
  if [ -n "$RUNNER_ENVIRONMENT" ]; then
    if [ -f "${RUNNER_ENVIRONMENT}/${RUNNER_ID}.tkn" ]; then
      if [ -n "${RUNNER_SECRET:-}" ]; then
        verbose "Requesting termination via ${RUNNER_ENVIRONMENT}/${RUNNER_ID}.trm"
        printf %s\\n "$RUNNER_SECRET" > "${RUNNER_ENVIRONMENT}/${RUNNER_ID}.trm"
      elif [ -n "$RUNNER_PID" ]; then
        kill_tree "$RUNNER_PID"
      fi
      if [ "$RUNNER_PID" ]; then
        # shellcheck disable=SC2046 # We want to wait for all children
        waitpid $(ps_tree "$RUNNER_PID"|tac)
      else
        warning "No PID to wait for"
      fi
    elif [ -n "$RUNNER_PID" ]; then
      kill_tree "$RUNNER_PID"
      # shellcheck disable=SC2046 # We want to wait for all children
      waitpid $(ps_tree "$RUNNER_PID"|tac)
    fi
  elif [ -n "$RUNNER_PID" ]; then
    kill_tree "$RUNNER_PID"
    # shellcheck disable=SC2046 # We want to wait for all children
    waitpid $(ps_tree "$RUNNER_PID"|tac)
  fi
}

cleanup() {
  trap '' EXIT
  if [ -n "${RUNNER_PID:-}" ]; then
    vm_terminate
  fi
  if [ -n "${RUNNER_ID:-}" ]; then
    vm_delete "$RUNNER_ID"
  fi
}

trap cleanup EXIT


iteration=0
while true; do
  RUNNER_ID="${loop}-$(random_string)"
  vm_create "${RUNNER_ID}"
  vm_start "${RUNNER_ID}"
  vm_delete "${RUNNER_ID}"
  RUNNER_ID=

  if [ "$RUNNER_REPEAT" -gt 0 ]; then
    iteration=$((iteration+1))
    if [ "$iteration" -ge "$RUNNER_REPEAT" ]; then
      verbose "Reached maximum number of iterations ($RUNNER_REPEAT)"
      break
    fi
  fi

  if [ -n "$RUNNER_ENVIRONMENT" ]; then
    if [ -f "${RUNNER_ENVIRONMENT}/${RUNNER_ID}.brk" ]; then
      break=$(cat "${RUNNER_ENVIRONMENT}/${RUNNER_ID}.brk")
      if [ "$break" = "$RUNNER_SECRET" ]; then
        verbose "Break file found, stopping runner loop"
        break
      else
        warning "Break file found at ${RUNNER_ENVIRONMENT}/${RUNNER_ID}.brk, but it does not match the secret"
      fi
    fi
  fi
done
