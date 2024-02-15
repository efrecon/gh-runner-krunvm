#!/bin/sh


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

# shellcheck disable=SC2120 # Function has good default.
random_string() {
  LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "${1:-12}"
}

usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 -- ${KRUNVM_RUNNER_DESCR:-"Part of the gh-krunvm-runner project"}" && \
    grep "[[:space:]].) #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-zA-Z-])\)/-\1/'
  if [ -n "${2:-}" ]; then
    printf '\nCurrent state:\n'
    set | grep -E "^${2}_" | grep -v 'TOKEN' | sed -E 's/^([A-Z])/  \1/g'
  fi
  exit "${1:-0}"
}

check_command() {
  trace "Checking $1 is an accessible command"
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Command not found: $1"
  fi
}

# Get the value of a variable in an env file. The function enforces sourcing in
# a separate process to avoid leaking out the sources variables.
get_env() (
  if [ "$#" -ge 2 ]; then
    if [ -f "$1" ]; then
      # shellcheck disable=SC1090 # We want to source the file. Danger zone!
      . "$1"

      eval printf %s "\$$2" || true
    fi
  fi
)

run_krunvm() {
  debug "Running krunvm $*"
  buildah unshare krunvm "$@"
}

# Wait for a path to exist
# $1 is the test to perform, e.g. -f for file, -d for directory, etc.
# $2 is the path to wait for
# $3 is the timeout in seconds
# $4 is the interval in seconds
wait_path() {
  _interval="${4:-1}"
  _elapsed=0

  while ! test "$1" "$2"; do
    if [ "$_elapsed" -ge "${3:-60}" ]; then
      error "Timeout waiting for $2"
    fi
    _elapsed=$((_elapsed+_interval))
    sleep "$_interval"
    debug "Waiting for $2"
  done
}

# PML: Poor Man's Logging
_log() {
  # Capture level and shift it away, rest will be passed blindly to printf
  _lvl=${1:-LOG}; shift
  if [ -z "${KRUNVM_RUNNER_BIN:-}" ]; then
    KRUNVM_RUNNER_BIN=$(basename "$0")
    KRUNVM_RUNNER_BIN=${KRUNVM_RUNNER_BIN%.sh}
  fi
  # shellcheck disable=SC2059 # We want to expand the format string
  printf '[%s] [%s] [%s] %s\n' \
    "${KRUNVM_RUNNER_BIN:-$(basename "$0")}" \
    "$_lvl" \
    "$(date +'%Y%m%d-%H%M%S')" \
    "$(printf "$@")" \
    >&"$KRUNVM_RUNNER_LOG"
}
trace() { if [ "${KRUNVM_RUNNER_VERBOSE:-0}" -ge "3" ]; then _log TRC "$@"; fi; }
debug() { if [ "${KRUNVM_RUNNER_VERBOSE:-0}" -ge "2" ]; then _log DBG "$@"; fi; }
verbose() { if [ "${KRUNVM_RUNNER_VERBOSE:-0}" -ge "1" ]; then _log NFO "$@"; fi; }
info() { if [ "${KRUNVM_RUNNER_VERBOSE:-0}" -ge "1" ]; then _log NFO "$@"; fi; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }
