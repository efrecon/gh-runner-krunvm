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
TOKEN_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(abspath "$0")")")" && pwd -P )

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
TOKEN_VERBOSE=${TOKEN_VERBOSE:-0}

# Where to send logs
TOKEN_LOG=${TOKEN_LOG:-2}

# GitHub host, e.g. github.com or github.example.com
TOKEN_GITHUB=${TOKEN_GITHUB:-"github.com"}

# Version of the GitHub API to use
TOKEN_API_VERSION=${TOKEN_API_VERSION:-"v3"}

# PAT to acquire the runner token with
TOKEN_PAT=${TOKEN_PAT:-""}

# Scope of the runner, one of: repo, org or enterprise
TOKEN_SCOPE=${TOKEN_SCOPE:-"repo"}

# Name of organisation, enterprise or repo to attach the runner to, when
# relevant scope.
TOKEN_PRINCIPAL=${TOKEN_PRINCIPAL:-""}

# shellcheck source=../lib/common.sh
. "$TOKEN_ROOTDIR/../lib/common.sh"

# shellcheck disable=SC2034 # Used in sourced scripts
KRUNVM_RUNNER_MAIN="Acquire a runner token from GitHub API"

while getopts "g:l:p:s:T:vh-" opt; do
  case "$opt" in
    g) # GitHub host
      TOKEN_GITHUB="$OPTARG";;
    l) # Where to send logs
      TOKEN_LOG="$OPTARG";;
    p) # Principal to authorise the runner for, name of repo, org or enterprise
      TOKEN_PRINCIPAL="$OPTARG";;
    s) # Scope of the token, one of repo, org or enterprise
      TOKEN_SCOPE="$OPTARG";;
    T) # Authorization token at the GitHub API
      TOKEN_PAT="$OPTARG";;
    v) # Increase verbosity, will otherwise log on errors/warnings only
      TOKEN_VERBOSE=$((TOKEN_VERBOSE+1));;
    h) # Print help and exit
      usage;;
    -) # End of options, everything after are options blindly passed to program before list of files
      break;;
    ?)
      usage 1;;
  esac
done
shift $((OPTIND-1))

# Pass logging configuration and level to imported scripts
KRUNVM_RUNNER_LOG=$TOKEN_LOG
KRUNVM_RUNNER_VERBOSE=$TOKEN_VERBOSE

if [ -z "$TOKEN_PRINCIPAL" ]; then
  error "Principal must be set to name of repo, org or enterprise"
fi

# Set the API URL based on the GitHub host
if [ "$TOKEN_GITHUB" = "github.com" ]; then
  TOKEN_APIURL="https://api.${TOKEN_GITHUB}"
else
  TOKEN_APIURL="https://${TOKEN_GITHUB}/api/${TOKEN_API_VERSION}"
fi

# Construct the URL to request the registration token from
case "$TOKEN_SCOPE" in
  org*)
    TOKEN_URL="${TOKEN_APIURL}/orgs";;
  ent*)
    TOKEN_URL="${TOKEN_APIURL}/enterprises";;
  rep*)
    TOKEN_URL="${TOKEN_APIURL}/repos";;
  *)
    error "Invalid scope, must be one of repo, org or enterprise";;
esac
TOKEN_URL=${TOKEN_URL}/${TOKEN_PRINCIPAL}/actions/runners/registration-token

curl \
  -fsSL \
  -XPOST \
  -H "Content-Length: 0" \
  -H "Authorization: token ${TOKEN_PAT}" \
  -H "Accept: application/vnd.github.${TOKEN_API_VERSION}+json" \
  "$TOKEN_URL" |
  jq -r '.token'