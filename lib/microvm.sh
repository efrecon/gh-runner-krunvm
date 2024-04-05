#!/bin/sh

# This implements an API to manage microVMs using krunvm and podman.


# Runtime to use for microVMs: podman+krun, krunvm. When empty, it will be
# automatically selected.
: "${KRUNVM_RUNNER_RUNTIME:=""}"

# Run krunvm with the provided arguments, behind a buildah unshare.
run_krunvm() {
  debug "Running krunvm $*"
  buildah unshare krunvm "$@"
}


# Automatically select a microVM runtime based on the available commands. Set
# the KRUNVM_RUNNER_RUNTIME variable.
_microvm_runtime_auto() {
  if check_command -s -- krun; then
    check_command podman
    KRUNVM_RUNNER_RUNTIME="podman+krun"
  elif check_command -s -- krunvm; then
    check_command buildah
    KRUNVM_RUNNER_RUNTIME="krunvm"
  fi
  info "Automatically selected $KRUNVM_RUNNER_RUNTIME to handle microVMs"
}


# Set the microVM runtime to use. When no argument is provided, it will try to
# automatically detect it based on the available commands.
# shellcheck disable=SC2120
microvm_runtime() {
  # Pick runtime provided as an argument, when available.
  [ "$#" -gt 0 ] && KRUNVM_RUNNER_RUNTIME="$1"

  # When no runtime is provided, try to auto-detect it.
  [ -z "${KRUNVM_RUNNER_RUNTIME:-""}" ] && _microvm_runtime_auto

  # Enforce podman+krun as soon as anything starting podman is provided.
  [ "${KRUNVM_RUNNER_RUNTIME#podman}" != "$KRUNVM_RUNNER_RUNTIME" ] && KRUNVM_RUNNER_RUNTIME="podman+krun"

  # Check if the runtime is valid.
  case "$KRUNVM_RUNNER_RUNTIME" in
    podman*)
      check_command podman
      check_command krun
      ;;
    krunvm)
      check_command krunvm
      check_command buildah
      ;;
    *)
      error "Unknown microVM runtime: $KRUNVM_RUNNER_RUNTIME"
      ;;
  esac
}


# List all microVMs.
microvm_list() {
  [ -z "$KRUNVM_RUNNER_RUNTIME" ] && microvm_runtime
  case "$KRUNVM_RUNNER_RUNTIME" in
    podman*)
      podman ps -a --format "{{.Names}}"
      ;;
    krunvm)
      run_krunvm list
      ;;
  esac
}


_krunvm_create() {
  KRUNVM_RUNNER_IMAGE=$1
  verbose "Creating microVM '${KRUNVM_RUNNER_NAME}', $KRUNVM_RUNNER_CPUS vCPUs, ${KRUNVM_RUNNER_MEM}M memory"
  # Note: reset arguments!
  set -- \
    --cpus "$KRUNVM_RUNNER_CPUS" \
    --mem "$KRUNVM_RUNNER_MEM" \
    --dns "$KRUNVM_RUNNER_DNS" \
    --name "$KRUNVM_RUNNER_NAME"
  if [ -n "$KRUNVM_RUNNER_VOLS" ]; then
    while IFS= read -r mount || [ -n "$mount" ]; do
      if [ -n "$mount" ]; then
        set -- "$@" --volume "$mount"
      fi
    done <<EOF
$(printf %s\\n "$KRUNVM_RUNNER_VOLS")
EOF
  fi
  run_krunvm create "$KRUNVM_RUNNER_IMAGE" "$@"
}


microvm_run() {
  [ -z "$KRUNVM_RUNNER_RUNTIME" ] && microvm_runtime

  OPTIND=1
  KRUNVM_RUNNER_CPUS=0
  KRUNVM_RUNNER_MEM=0
  KRUNVM_RUNNER_DNS="1.1.1.1"
  KRUNVM_RUNNER_NAME=""
  KRUNVM_RUNNER_VOLS=""
  KRUNVM_RUNNER_ENTRYPOINT=""
  while getopts "c:d:e:m:n:v:-" _opt; do
    case "$_opt" in
      c) # Number of CPUs
        KRUNVM_RUNNER_CPUS="$OPTARG";;
      d) # DNS Server
        KRUNVM_RUNNER_DNS="$OPTARG";;
      e) # Entrypoint
        KRUNVM_RUNNER_ENTRYPOINT="$OPTARG";;
      m) # Memory in Mb
        KRUNVM_RUNNER_MEM="$OPTARG";;
      n) # Name of container/VM
        KRUNVM_RUNNER_NAME="$OPTARG";;
      v) # Volumes to mount
        if [ -z "$KRUNVM_RUNNER_VOLS" ]; then
          KRUNVM_RUNNER_VOLS="$OPTARG"
        else
          KRUNVM_RUNNER_VOLS="$(printf %s\\n%s\\n "$KRUNVM_RUNNER_VOLS" "$OPTARG")"
        fi;;
      -) # End of options, everything after is the image and arguments to run
        break;;
      ?)
        error "$_opt is an unrecognised option";;
    esac
  done
  shift $((OPTIND-1))
  if [ "$#" -lt 1 ]; then
    error "No image specified"
  fi
  [ -z "$KRUNVM_RUNNER_NAME" ] && error "No name specified for microVM"

  case "$KRUNVM_RUNNER_RUNTIME" in
    podman*)
      set -- \
        --runtime "krun" \
        --rm \
        --tty \
        --name "$KRUNVM_RUNNER_NAME" \
        --cpus "$KRUNVM_RUNNER_CPUS" \
        --memory "${KRUNVM_RUNNER_MEM}m" \
        --dns "$KRUNVM_RUNNER_DNS" \
        --entrypoint "$KRUNVM_RUNNER_ENTRYPOINT" \
        "$@"
      if [ -n "$KRUNVM_RUNNER_VOLS" ]; then
        while IFS= read -r mount || [ -n "$mount" ]; do
          if [ -n "$mount" ]; then
            set -- --volume "$mount" "$@"
          fi
        done <<EOF
$(printf %s\\n "$KRUNVM_RUNNER_VOLS")
EOF
      fi
      verbose "Starting container '${KRUNVM_RUNNER_NAME}' with entrypoint $KRUNVM_RUNNER_ENTRYPOINT"
      podman run "$@"
      ;;
    krunvm)
      _krunvm_create "$1"
      shift

      verbose "Starting microVM '${KRUNVM_RUNNER_NAME}' with entrypoint $KRUNVM_RUNNER_ENTRYPOINT"
      optstate=$(set +o)
      set -m; # Disable job control
      run_krunvm start "$KRUNVM_RUNNER_NAME" "$RUNNER_ENTRYPOINT" -- "$@" </dev/null &
      KRUNVM_RUNNER_PID=$!
      eval "$optstate"; # Restore options
      verbose "Started microVM '$KRUNVM_RUNNER_NAME' with PID $KRUNVM_RUNNER_PID"
      wait "$KRUNVM_RUNNER_PID"
      KRUNVM_RUNNER_PID=
      ;;
    *)
      error "Unknown microVM runtime: $KRUNVM_RUNNER_RUNTIME"
      ;;
  esac
}


microvm_wait() {
  [ -z "$KRUNVM_RUNNER_RUNTIME" ] && microvm_runtime

  if [ "$#" -lt 1 ]; then
    error "No name specified"
  fi

  case "$KRUNVM_RUNNER_RUNTIME" in
    podman*)
      podman wait "$1";;
    krunvm)
      if [ -n "$KRUNVM_RUNNER_PID" ]; then
        # shellcheck disable=SC2046 # We want to wait for all children
        waitpid $(ps_tree "$KRUNVM_RUNNER_PID"|tac)
        KRUNVM_RUNNER_PID=
      fi
      ;;
    *)
      error "Unknown microVM runtime: $KRUNVM_RUNNER_RUNTIME"
      ;;
  esac
}


# NOTE: we won't be using this much, since we terminate through the .trm file in most cases.
microvm_stop() {
  [ -z "$KRUNVM_RUNNER_RUNTIME" ] && microvm_runtime

  if [ "$#" -lt 1 ]; then
    error "No name specified"
  fi

  case "$KRUNVM_RUNNER_RUNTIME" in
    podman*)
      # TODO: Specify howlog to wait between TERM and KILL?
      podman stop "$1";;
    krunvm)
      if [ -n "$KRUNVM_RUNNER_PID" ]; then
        kill_tree "$KRUNVM_RUNNER_PID"
        # shellcheck disable=SC2046 # We want to wait for all children
        microvm_wait "$1"
      fi
      ;;
    *)
      error "Unknown microVM runtime: $KRUNVM_RUNNER_RUNTIME"
      ;;
  esac
}

microvm_delete() {
  [ -z "$KRUNVM_RUNNER_RUNTIME" ] && microvm_runtime

  if [ "$#" -lt 1 ]; then
    error "No name specified"
  fi

  case "$KRUNVM_RUNNER_RUNTIME" in
    podman*)
      verbose "Removing container '$1'"
      podman rm -f "$1";;
    krunvm)
      verbose "Removing microVM '$1'"
      run_krunvm delete "$1";;
    *)
      error "Unknown microVM runtime: $KRUNVM_RUNNER_RUNTIME"
      ;;
  esac
}

microvm_pull() {
  [ -z "$KRUNVM_RUNNER_RUNTIME" ] && microvm_runtime

  if [ "$#" -lt 1 ]; then
    error "No image name specified"
  fi

  verbose "Pulling image(s) '$*'"
  case "$KRUNVM_RUNNER_RUNTIME" in
    podman*)
      podman pull "$@";;
    krunvm)
      buildah pull "$@";;
    *)
      error "Unknown microVM runtime: $KRUNVM_RUNNER_RUNTIME"
      ;;
  esac

}