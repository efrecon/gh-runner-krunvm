#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
TOKEN_VERBOSE=${TOKEN_VERBOSE:-0}

# Where to send logs
TOKEN_LOG=${TOKEN_LOG:-2}

TOKEN_GITHUB=${TOKEN_GITHUB:-"github.com"}

TOKEN_API_VERSION=${TOKEN_API_VERSION:-"v3"}

TOKEN_PAT=${TOKEN_PAT:-""}

TOKEN_SCOPE=${TOKEN_SCOPE:-"repo"}

# Name of organisation, enterprise or repo to attach the runner to, when
# relevant scope.
TOKEN_PRINCIPAL=${TOKEN_PRINCIPAL:-""}

usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 install the GitHub runner" && \
    grep "[[:space:]].) #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-zA-Z-])\)/-\1/'
  exit "${1:-0}"
}

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

# PML: Poor Man's Logging
_log() {
  printf '[%s] [%s] [%s] %s\n' \
    "$(basename "$0")" \
    "${2:-LOG}" \
    "$(date +'%Y%m%d-%H%M%S')" \
    "${1:-}" \
    >&"$TOKEN_LOG"
}
trace() { if [ "${TOKEN_VERBOSE:-0}" -ge "3" ]; then _log "$1" TRC; fi; }
debug() { if [ "${TOKEN_VERBOSE:-0}" -ge "2" ]; then _log "$1" DBG; fi; }
verbose() { if [ "${TOKEN_VERBOSE:-0}" -ge "1" ]; then _log "$1" NFO; fi; }
warn() { _log "$1" WRN; }
error() { _log "$1" ERR && exit 1; }

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