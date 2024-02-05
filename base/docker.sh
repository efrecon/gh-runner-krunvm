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

# Look for the real docker client executable in the PATH variable. This will not
# work if there is a directory containing a line break in the PATH (but...
# why?!)
__DOCKER_DOCKER=$(find_exec docker.orig)
if [ -z "${__DOCKER_DOCKER:-}" ]; then
  __DOCKER_DOCKER=$(find_exec docker)
  if [ -z "${__DOCKER_DOCKER:-}" ]; then
    printf %s\\n "No docker binary found in PATH" >&2
    exit 1
  fi
fi

# Parse the global options that the docker client understands.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) # Path to the config file
      __DOCKER_CONFIG="$2"; shift 2;;
    --config=*) # Path to the config file
      __DOCKER_CONFIG="${1#*=}"; shift 1;;

    -c | --context) # Name of the context to use
      __DOCKER_CONTEXT="$2"; shift 2;;
    --context=*) # Name of the context to use
      __DOCKER_CONTEXT="${1#*=}"; shift 1;;

    -D | --debug) # Enable debug mode
      __DOCKER_DEBUG=1; shift 1;;

    -H | --host) # Daemon socket(s) to connect to
      __DOCKER_HOST="$2"; shift 2;;
    --host=*) # Daemon socket(s) to connect to
      __DOCKER_HOST="${1#*=}"; shift 1;;

    -l | --log-level) # Set the logging level
      __DOCKER_LOG_LEVEL="$2"; shift 2;;
    --log-level=*) # Set the logging level
      __DOCKER_LOG_LEVEL="${1#*=}"; shift 1;;

    --tls) # Use TLS; implied by --tlsverify
      __DOCKER_TLS=1; shift 1;;

    --tlscacert) # Trust certs signed only by this CA
      __DOCKER_TLS_CA_CERT="$2"; shift 2;;
    --tlscacert=*) # Trust certs signed only by this CA
      __DOCKER_TLS_CA_CERT="${1#*=}"; shift 1;;

    --tlscert) # Path to TLS certificate file
      __DOCKER_TLS_CERT="$2"; shift 2;;
    --tlscert=*) # Path to TLS certificate file
      __DOCKER_TLS_CERT="${1#*=}"; shift 1;;

    --tlskey) # Path to TLS key file
      __DOCKER_TLS_KEY="$2"; shift 2;;
    --tlskey=*) # Path to TLS key file
      __DOCKER_TLS_KEY="${1#*=}"; shift 1;;

    --tlsverify) # Use TLS and verify the remote
      __DOCKER_TLS_VERIFY=1; shift 1;;

    -v | --version) # Print version information and quit
      __DOCKER_VERSION=1; shift 1;;
    --)
        shift; break;;
    -*)
        exec "$__DOCKER_DOCKER" "$@";;
    *)
        break;;
  esac
done

# Nothing more? Show the help
if [ "$#" = 0 ]; then
  exec "$__DOCKER_DOCKER" help
fi

# Run the docker client with the options we have parsed
run_docker() {
  if [ -n "${__DOCKER_CONFIG:-}" ]; then
    set -- --config "${__DOCKER_CONFIG}" "$@"
  fi
  if [ -n "${__DOCKER_CONTEXT:-}" ]; then
    set -- --context "${__DOCKER_CONTEXT}" "$@"
  fi
  if [ "${__DOCKER_DEBUG:-0}" = 1 ]; then
    set -- --debug "$@"
  fi
  if [ -n "${__DOCKER_HOST:-}" ]; then
    set -- --host "${__DOCKER_HOST}" "$@"
  fi
  if [ -n "${__DOCKER_LOG_LEVEL:-}" ]; then
    set -- --log-level "${__DOCKER_LOG_LEVEL}" "$@"
  fi
  if [ "${__DOCKER_TLS:-0}" = 1 ]; then
    set -- --tls "$@"
  fi
  if [ -n "${__DOCKER_TLS_CA_CERT:-}" ]; then
    set -- --tlscacert "${__DOCKER_TLS_CA_CERT}" "$@"
  fi
  if [ -n "${__DOCKER_TLS_CERT:-}" ]; then
    set -- --tlscert "${__DOCKER_TLS_CERT}" "$@"
  fi
  if [ -n "${__DOCKER_TLS_KEY:-}" ]; then
    set -- --tlskey "${__DOCKER_TLS_KEY}" "$@"
  fi
  if [ "${__DOCKER_TLS_VERIFY:-0}" = 1 ]; then
    set -- --tlsverify "$@"
  fi
  if [ "${__DOCKER_VERSION:-0}" = 1 ]; then
    set -- --version "$@"
  fi
  # Execute the docker client with the options we have parsed, in place.
  exec "$__DOCKER_DOCKER" "$@"
}

# Pick the command (and perhaps sub command). When it is a container run
# command, automatically add --network host. Otherwise, just run as-is.
cmd=$1; shift
case "$cmd" in
  container)
    sub=$1; shift
    case "$sub" in
      run)
        set -- "$cmd" "$sub" --network host "$@"
        run_docker "$@"
        ;;
      *)
        set -- "$cmd" "$sub" "$@"
        run_docker "$@"
        ;;
    esac
    ;;
  run)
    set -- "$cmd"  --network host "$@"
    run_docker "$@"
    ;;
  *)
    set -- "$cmd" "$@"
    run_docker "$@"
    ;;
esac
