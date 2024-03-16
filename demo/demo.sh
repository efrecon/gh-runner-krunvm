#!/usr/bin/env bash

DEMO_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )

. "$DEMO_ROOTDIR/demo-magic/demo-magic.sh"

DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

if [ -z "${RUNNER_PAT:-}" ]; then
  echo "Create a RUNNER_PAT environment variable with a GitHub Personal Access Token"
  exit 1
fi

clear

pe "# Let's start one (short-lived) runner for this repository"
pe "# A PAT is present in the environment variable RUNNER_PAT"
pe "# Just for the demo, we will use two seldom used options to show teardown"
pe "# -k 70: to run for 70 seconds only, the default is to run forever"
pe "# -r 1: to run once only, the default is to run forever"
pe "./orchestrator.sh -v -- -r 1 -k 70 -p efrecon/gh-runner-krunvm"
