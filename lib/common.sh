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
  echo "$0 -- ${KRUNVM_RUNNER_MAIN:-"Part of the gh-krunvm-runner project"}" && \
    grep "[[:space:]].) #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-zA-Z-])\)/-\1/'
  exit "${1:-0}"
}

check_command() {
  trace "Checking $1 is an accessible command"
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Command not found: $1"
  fi
}

# Get the value of one variable in os-release. Empty in all error cases
get_release() (
  if [ -n "${1:-}" ] && [ -f "/etc/os-release" ]; then
    . /etc/os-release

    eval printf %s "\$$1" || true
  fi
)

run_krunvm() {
  buildah unshare krunvm "$@"
}

# PML: Poor Man's Logging
_log() {
  # Capture level and shift it away, rest will be passed blindly to printf
  _lvl=${1:-LOG}; shift
  # shellcheck disable=SC2059 # We want to expand the format string
  printf '[%s] [%s] [%s] %s\n' \
    "$(basename "$0")" \
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
