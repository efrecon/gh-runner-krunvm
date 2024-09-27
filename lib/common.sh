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
  LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "${1:-7}"
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
  OPTIND=1
  _hard=1
  _warn=0
  while getopts "sw-" _opt; do
    case "$_opt" in
      s) # Soft check, return an error code instead of exiting
        _hard=0;;
      w) # Print a warning when soft checking
        _warn=1;;
      -) # End of options, everything after is the command
        break;;
      ?)
        error "$_opt is an unrecognised option";;
    esac
  done
  shift $((OPTIND-1))
  if [ -z "$1" ]; then
    error "No command specified for checking"
  fi
  trace "Checking $1 is an accessible command"
  if ! command -v "$1" >/dev/null 2>&1; then
    if is_true "$_hard"; then
      error "Command not found: $1"
    elif is_true "$_warn"; then
      warn "Command not found: $1"
    fi
    return 1
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

tac() {
  awk '{ buffer[NR] = $0; } END { for(i=NR; i>0; i--) { print buffer[i] } }'
}

# This is the same as pgrep -P, but using ps and awk. The option (and keywords)
# used also exist on macOS, so this implementation should be cross platform.
pgrep_P() {
  ps -A -o pid,ppid | awk -v pid="$1" '$2 == pid { print $1 }'
}

ps_tree() {
  if [ -n "$1" ]; then
    printf %s\\n "$1"
    for _pid in $(pgrep_P "$1"); do
      ps_tree "$_pid"
    done
  fi
}

running() {
  # Construct a comma separated list of pids to wait for
  _pidlist=
  for _pid; do
    _pidlist="${_pidlist},${_pid}"
  done

  # Construct the list of those pids that are still running
  ps -p "${_pidlist#,}" -o pid= 2>/dev/null | awk '{ print $1 }'
}

waitpid() {
  # Construct the list of those pids that are still running
  _running=$(running "$@")

  # If not empty, sleep and try again with the list of running pids (so we avoid
  # having the same PID that would reappear -- very unlikely)
  if [ -n "$_running" ]; then
    sleep 1
    # shellcheck disable=SC2086 # We want to expand the list of pids
    waitpid $_running
  fi
}

kill_tree() {
  verbose "Killing process tree for $1"
  for pid in $(ps_tree "$1"|tac); do
    debug "Killing process $pid"
    kill -s "${2:-TERM}" -- "$pid" 2>/dev/null
  done
}


find_pattern() {
  _type=$(to_lower "${2:-f}")
  find "$(dirname "$1")/" \
    -maxdepth 1 \
    -name "$(basename "$1")" \
    -type "${_type#-}" 2>/dev/null
}


# Wait for a path to exist
# $1 is the test to perform, e.g. -f for file (default), -d for directory, etc.
# $2 is the path/pattern to wait for
# $3 is the timeout in seconds
# $4 is the interval in seconds
wait_path() {
  _interval="${4:-1}"
  _elapsed=0

  while [ -z "$(find_pattern "$2" "$1")" ]; do
    if [ "${3:-60}" -gt 0 ] && [ "$_elapsed" -ge "${3:-60}" ]; then
      error "Timeout waiting for $2"
    fi
    _elapsed=$((_elapsed+_interval))
    sleep "$_interval"
    debug "Waiting for $2"
  done
}

check_number() {
  if ! printf %d\\n "$1" >/dev/null 2>&1; then
    if [ -n "${2:-}" ]; then
      error "$2 is an invalid number: $1"
    else
      error "Invalid number: $1"
    fi
  fi
}

check_positive_number() {
  check_number "$1" "$2"
  if [ "$1" -le 0 ]; then
    if [ -n "${2:-}" ]; then
      error "$2 must be a positive number: $1"
    else
      error "Invalid positive number: $1"
    fi
  fi
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

sublog() {
  # Eagerly wait for the log file to exist
  while ! [ -f "${1-0}" ]; do sleep 0.1; done
  debug "$1 now present on disk"

  # Then reroute its content through our logging printf style
  tail -n +0 -f "$1" 2>/dev/null | while IFS= read -r line; do
    if [ -n "$line" ]; then
      printf '[%s] [%s] %s\n' \
        "${2:-}@${KRUNVM_RUNNER_BIN:-$(basename "$0")}" \
        "$(date +'%Y%m%d-%H%M%S')" \
        "$line" \
        >&"$KRUNVM_RUNNER_LOG"
    fi
  done
}
