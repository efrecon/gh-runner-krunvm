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

# shellcheck source=lib/common.sh
. "$ORCHESTRATOR_ROOTDIR/lib/common.sh"

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
ORCHESTRATOR_VERBOSE=${ORCHESTRATOR_VERBOSE:-0}

# Where to send logs
ORCHESTRATOR_LOG=${ORCHESTRATOR_LOG:-2}

# Number of runners to create
ORCHESTRATOR_RUNNERS=${ORCHESTRATOR_RUNNERS:-1}

# Prefix to use for the VM name. The VM name will be $ORCHESTRATOR_PREFIX-xxx.
# All VMs prefixed with this name will be deleted on exit.
ORCHESTRATOR_PREFIX=${ORCHESTRATOR_PREFIX:-"GH-runner"}

# Should the runner be isolated in its own environment. This will pass all
# configuration down to the runner starter script as an environment variable to
# avoid leaking secrets in the command line. The file will be removed as soon as
# used.
ORCHESTRATOR_ISOLATION=${ORCHESTRATOR_ISOLATION:-"1"}

# Number of seconds to sleep between microVM creation at start, unless isolation
# has been turned on.
ORCHESTRATOR_SLEEP=${ORCHESTRATOR_SLEEP:-"30"}

# shellcheck disable=SC2034 # Used in sourced scripts
KRUNVM_RUNNER_DESCR="Run krunvm-based GitHub runners on a single host"


while getopts "s:Il:n:p:vh-" opt; do
  case "$opt" in
    s) # Number of seconds to sleep between microVM creation at start, when no isolation
      ORCHESTRATOR_SLEEP="$OPTARG";;
    I) # Turn off variables isolation (not recommended, security risk)
      ORCHESTRATOR_ISOLATION=0;;
    l) # Where to send logs
      ORCHESTRATOR_LOG="$OPTARG";;
    n) # Number of runners to create
      ORCHESTRATOR_RUNNERS="$OPTARG";;
    p) # Prefix to use for the VM name
      ORCHESTRATOR_PREFIX="$OPTARG";;
    v) # Increase verbosity, will otherwise log on errors/warnings only
      ORCHESTRATOR_VERBOSE=$((ORCHESTRATOR_VERBOSE+1));;
    h) # Print help and exit
      usage 0 "(ORCHESTRATOR|RUNNER)";;
    -) # End of options. All subsequent arguments are passed to the runner.sh script
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
  trap '' EXIT

  for pid in $ORCHESTRATOR_PIDS; do
    verbose "Killing runner loop $pid"
    kill "$pid" 2>/dev/null || true
  done
  verbose "Waiting for runners to die"
  # shellcheck disable=SC2086 # We want to wait for all pids
  waitpid $ORCHESTRATOR_PIDS

  if run_krunvm list | grep -qE "^${ORCHESTRATOR_PREFIX}-"; then
    while IFS= read -r vm; do
      verbose "Removing microVM $vm"
      run_krunvm delete "$vm"
    done <<EOF
$(run_krunvm list | grep -E "^${ORCHESTRATOR_PREFIX}-")
EOF
  fi

  if [ -n "${ORCHESTRATOR_ENVIRONMENT:-}" ]; then
    verbose "Removing isolation environment $ORCHESTRATOR_ENVIRONMENT"
    rm -rf "$ORCHESTRATOR_ENVIRONMENT"
  fi
}

check_command buildah
check_command krunvm

check_positive_number "$ORCHESTRATOR_RUNNERS" "Number of runners"

# Create isolation mount point
if [ "$ORCHESTRATOR_ISOLATION" = 1 ]; then
  ORCHESTRATOR_ENVIRONMENT=$(mktemp -d)
  verbose "Creating $ORCHESTRATOR_RUNNERS isolated runner loops (using: $ORCHESTRATOR_ENVIRONMENT)"
else
  verbose "Creating $ORCHESTRATOR_RUNNERS insecure runner loops"
fi

trap cleanup EXIT

# Pass essential variables, verbosity and log configuration to main runner
# script.
RUNNER_PREFIX=$ORCHESTRATOR_PREFIX
RUNNER_ENVIRONMENT="${ORCHESTRATOR_ENVIRONMENT:-}"
RUNNER_VERBOSE=$ORCHESTRATOR_VERBOSE
RUNNER_LOG=$ORCHESTRATOR_LOG
export RUNNER_PREFIX RUNNER_ENVIRONMENT RUNNER_VERBOSE RUNNER_LOG

# Create runner loops in the background. One per runner. Each loop will
# indefinitely create ephemeral runners. Looping is implemented in runner.sh,
# in the same directory as this script.
for i in $(seq 1 "$ORCHESTRATOR_RUNNERS"); do
  # Launch a runner loop in the background and collect its PID in the
  # ORCHESTRATOR_PIDS variable.
  verbose "Creating runner loop $i"
  "$ORCHESTRATOR_ROOTDIR/runner.sh" "$@" -- "$i" &
  if [ "$i" = "1" ]; then
    ORCHESTRATOR_PIDS="$!"
  else
    ORCHESTRATOR_PIDS="$ORCHESTRATOR_PIDS $!"
  fi

  # Wait for runner to be ready or have progressed somewhat before starting
  # the next one.
  if [ "$i" -lt "$ORCHESTRATOR_RUNNERS" ]; then
    # Wait for the runner token to be ready before starting the next runner,
    # or, at least, sleep for some time.
    if [ -n "${ORCHESTRATOR_ENVIRONMENT:-}" ]; then
      wait_path -f "${ORCHESTRATOR_ENVIRONMENT}/${i}-*.tkn" -1 5
      token=$(find_pattern "${ORCHESTRATOR_ENVIRONMENT}/${i}-*.tkn")
      rm -f "$token"
      verbose "Removed token file $token"
    elif [ -n "$ORCHESTRATOR_SLEEP" ] && [ "$ORCHESTRATOR_SLEEP" -gt 0 ]; then
      debug "Sleeping for $ORCHESTRATOR_SLEEP seconds"
      sleep "$ORCHESTRATOR_SLEEP"
    fi
  fi
done

# shellcheck disable=SC2086 # We want to wait for all pids
waitpid $ORCHESTRATOR_PIDS
cleanup
