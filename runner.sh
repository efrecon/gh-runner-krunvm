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

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
RUNNER_VERBOSE=${RUNNER_VERBOSE:-0}

# Where to send logs
RUNNER_LOG=${RUNNER_LOG:-2}

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

# Name of the microVM to run from
RUNNER_NAME=${RUNNER_NAME:-"runner"}

RUNNER_MOUNT=${RUNNER_MOUNT:-""}

# shellcheck source=lib/common.sh
. "$RUNNER_ROOTDIR/lib/common.sh"

# shellcheck disable=SC2034 # Used in sourced scripts
KRUNVM_RUNNER_MAIN="Create runners forever using krunvm"


while getopts "g:G:l:L:M:n:p:s:T:u:Uvh-" opt; do
  case "$opt" in
    g) # GitHub host, e.g. github.com or github.example.com
      RUNNER_GITHUB="$OPTARG";;
    G) # Group to attach the runner to
      RUNNER_GROUP="$OPTARG";;
    l) # Where to send logs
      RUNNER_LOG="$OPTARG";;
    L) # Comma separated list of labels to attach to the runner
      RUNNER_LABELS="$OPTARG";;
    M) # Mount passed to the microVM
      RUNNER_MOUNT="$OPTARG";;
    n) # Name of the microVM to run from
      RUNNER_NAME="$OPTARG";;
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
      RUNNER_VERBOSE=$((RUNNER_VERBOSE+1));;
    h) # Print help and exit
      usage;;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))

# Pass logging configuration and level to imported scripts
KRUNVM_RUNNER_LOG=$RUNNER_LOG
KRUNVM_RUNNER_VERBOSE=$RUNNER_VERBOSE

if [ -z "$RUNNER_MOUNT" ]; then
  runner=/opt/gh-runner-krunvm/bin/runner.sh
else
  runner=${RUNNER_MOUNT%/}/runner/runner.sh
fi
while true; do
  verbose "Starting microVM $RUNNER_NAME to run an ephemeral GitHub runner"
  run_krunvm start "$RUNNER_NAME" \
    "$runner" \
        -- \
        -e \
        -g "$RUNNER_GITHUB" \
        -G "$RUNNER_GROUP" \
        -l "$RUNNER_LOG" \
        -L "$RUNNER_LABELS" \
        -p "$RUNNER_PRINCIPAL" \
        -s "$RUNNER_SCOPE" \
        -T "$RUNNER_PAT" \
        -u "$RUNNER_USER" \
        -vv \
      -- \
        /opt/actions-runner/bin/Runner.Listener run --startuptype service
done