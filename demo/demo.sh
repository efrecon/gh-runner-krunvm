#!/usr/bin/env bash

DEMO_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )

. "$DEMO_ROOTDIR/demo-magic/demo-magic.sh"

DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

if [ -z "${RUNNER_PAT:-}" ]; then
  echo "Create a RUNNER_PAT environment variable with a GitHub Personal Access Token"
  exit 1
fi

clear

pe "# For the sake of the asciicast: PAT is present in RUNNER_PAT environment variable"
pe "# -r 1: to run once only, the default is to run forever"
pe "./orchestrator.sh -v -- -r 1 -p efrecon/gh-runner-krunvm"
